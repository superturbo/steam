require 'delegate'

require_relative '../../adapters/query/comparison'

module Locomotive::Steam
  module Models

    # Batches the has_many enumeration of one association name within one
    # bounded window.
    class HasManyPreloader

      # A conservative cardinality limit, not a byte guarantee: the shared
      # cache never maps more children than this.
      MAX_BATCHED_CHILDREN = 100

      # Composite components count as operands of the inverse ID filter.
      MAX_OWNER_OPERANDS = 100

      private_constant :MAX_BATCHED_CHILDREN, :MAX_OWNER_OPERANDS

      def initialize(entries)
        @entries        = entries
        @groups         = {}
        @children_count = 0
        @looked_up      = false
        @unbatchable    = {}
        @exhausted      = false
      end

      def source_for(association)
        Source.new(self, association)
      end

      # The ordered children of one owner; only a full enumeration batches.
      def children_for(association)
        repository = base(association)
        owner      = association.__owner__

        unless @groups.key?(owner)
          if @looked_up && !@unbatchable[owner] && !@exhausted
            batch(association, repository)
          else
            @looked_up = true
          end
        end

        return @groups[owner].map(&:dup) if @groups.key?(owner)

        read_owner(association, repository, owner)
      end

      # The current per-parent read, built on the shared configured base.
      def parent_repository_for(association)
        base(association).dup.tap do |repository|
          key = repository.k(association.__inverse_key__, :in)

          repository.local_conditions[key] = Array(association.__owner__._id).compact

          unless association.__declared_order__.blank?
            repository.local_conditions[:order_by] ||= association.__declared_order__
          end
        end
      end

      private

      # One batch per read: a probe bounded by the remaining budget, then a
      # find bounded the same way, discarded if a concurrent write slipped
      # children in between.
      def batch(association, repository)
        remaining = MAX_BATCHED_CHILDREN - @children_count

        return if remaining <= 0

        # The chunk starts at the owner whose read pays for the probe; the
        # owners a template already skipped are not its business.
        pending = pending_owners
        start   = pending.index(association.__owner__)
        pending = pending.drop(start) if start
        chunk   = owner_chunk(pending)

        # The count and fetch must beat the per-parent reads they replace.
        return if 2 >= chunk.length

        operands   = chunk.flat_map { |entry| Array(entry._id).compact }
        conditions = { repository.k(association.__inverse_key__, :in) => operands }
        observed   = repository.count_up_to(remaining + 1, conditions)

        # One failed probe closes shared batching for this whole window.
        return @exhausted = true if observed > remaining

        order    = association.__declared_order__
        children = repository.all(conditions.merge(order.blank? ? {} : { order_by: order })) { limit(remaining + 1) }

        return @exhausted = true if children.length > remaining

        index(association, chunk, children)
      end

      # Owners may share an identity component; the child then belongs to
      # every one of them, exactly as their per-parent reads would answer.
      def index(association, chunk, children)
        slots = Hash.new { |hash, key| hash[key] = [] }

        chunk.each do |entry|
          group = (@groups[entry] = [])
          owner_keys(entry).each { |key| slots[key] << group }
        end

        children.each do |child|
          slots[grouping_key(child[association.__inverse_key__])].each do |group|
            group << child
          end
        end

        @children_count += children.length
      end

      def pending_owners
        @entries.select do |entry|
          entry.respond_to?(:_id) && !@groups.key?(entry) && !@unbatchable[entry]
        end
      end

      def owner_chunk(pending)
        operands = 0

        pending.take_while do |entry|
          operands += Array(entry._id).compact.length
          operands <= MAX_OWNER_OPERANDS
        end
      end

      def read_owner(association, repository, owner)
        children = parent_repository_for(association).all

        if @children_count + children.length <= MAX_BATCHED_CHILDREN
          @groups[owner]   = children
          @children_count += children.length
        else
          # An owner that no longer fits this window's cache stays out of
          # later probes.
          @unbatchable[owner] = true
        end

        children.map(&:dup)
      end

      # Symbols and strings with the same spelling share a query identity.
      def owner_keys(owner)
        Array(owner._id).compact.map { |component| grouping_key(component) }
      end

      def grouping_key(component)
        Adapters::Query::Comparison.normalize_scalar(component)
      end

      # Preserve the configured target scope.
      def base(association)
        @repository ||= association.__configured_repository__.dup
      end

      # Full enumeration uses the window cache; inner windows and other
      # operations stay per-parent.
      class Source < SimpleDelegator

        def initialize(preloader, association)
          super(nil)
          @preloader, @association = preloader, association
        end

        def load_window(conditions, offset, limit)
          if conditions.blank? && limit.nil? && offset.to_i.zero?
            return @preloader.children_for(@association)
          end

          window_offset, window_limit = offset, limit

          __getobj__.all(conditions || {}) { offset(window_offset).limit(window_limit) }
        end

        def all(conditions = {}, &block)
          return __getobj__.all(conditions || {}, &block) if block || conditions.present?

          load_window(conditions, 0, nil)
        end

        def each(&block)
          all.each(&block)
        end

        def to_liquid
          Locomotive::Steam::Liquid::Drops::ContentEntryCollection.new(__getobj__.content_type, self)
        end

        def __getobj__
          @repository ||= @preloader.parent_repository_for(@association)
        end

      end

    end

  end
end
