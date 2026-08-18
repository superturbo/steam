require 'delegate'

module Locomotive::Steam
  module Models

    # Batches the many_to_many enumeration of one association name within
    # one bounded window.
    class ManyToManyPreloader

      # Keep $in batches below the measured planner crossover.
      BATCH_SIZE = 100

      # Composite aliases do not count toward the requested-ID limit.
      MAX_REQUESTED_IDS = 100

      private_constant :BATCH_SIZE, :MAX_REQUESTED_IDS

      CandidateScan = Struct.new(:candidates, :pending, :next_index, :first_unresolved_index,
                                 :overflowed, keyword_init: true)

      private_constant :CandidateScan

      def initialize(entries)
        @entries         = entries
        @cache           = {}
        @requested_count = 0
        @looked_up       = false
        @progress        = Hash.new(0)
      end

      def source_for(association)
        Source.new(self, association)
      end

      # Ordered targets of one owner. Apply offset after missing and hidden
      # targets are removed.
      def targets_for(association, offset, limit)
        return [] if limit == 0

        repository     = base(association)
        ids            = association.__owner_ids__
        required_count = limit && offset + limit
        found          = []
        seen_targets   = {}
        scanned        = 0
        resolved       = 0

        loop do
          capacity = MAX_REQUESTED_IDS - @requested_count
          need     = required_count && scanned + (required_count - found.length)
          walk     = walk_candidates(repository, ids, need, capacity)
          fresh    = walk.candidates.drop(scanned)
          before   = found.length

          if walk.overflowed
            usable = walk.candidates.drop(scanned).take_while { |id| @cache.key?(id) }

            usable.each do |id|
              target = @cache[id]
              next if target.nil? || seen_targets[target._id]

              seen_targets[target._id] = true
              found << target
            end

            return continued(association, repository, found, seen_targets,
                             walk.candidates.first(scanned) + usable,
                             walk.first_unresolved_index, offset, required_count)
          end

          break if fresh.empty?

          pending = fresh.reject { |id| @cache.key?(id) }
          fetch(association, repository, pending, offset, limit, capacity) if pending.any?

          # Both components of one composite identity answer the same target.
          fresh.each do |id|
            target = @cache[id]
            next if target.nil? || seen_targets[target._id]

            seen_targets[target._id] = true
            found << target
          end

          scanned  = walk.candidates.length
          resolved = walk.next_index
          @progress[association.__owner__] = scanned

          break if required_count && found.length >= required_count

          if pending.any? && found.length == before
            return continued(association, repository, found, seen_targets,
                             walk.candidates, resolved, offset, required_count)
          end
        end

        found.drop(offset).map(&:dup)
      end

      # Reuse the configured target repository for per-owner fallback.
      def parent_repository_for(association)
        ids = association.__owner_ids__

        base(association).dup.tap do |repository|
          repository.local_conditions[repository.k(:_id, :in)] = ids
          repository.id_order = ids
        end
      end

      private

      # Walks the raw ids once, stopping at the needed count or right before
      # the ID budget would be exceeded. Counting :window_slots skips a
      # cached absence: it takes no place in a window.
      def walk_candidates(repository, ids, need, capacity, counting: :candidates)
        candidates = []
        pending    = []
        seen       = {}
        boundary   = 0
        unresolved = nil
        counted    = 0

        ids.each_with_index do |id, raw_index|
          next if id.nil?

          key = repository.adapter.make_id(id)
          next if seen[key]

          cached = @cache.key?(key)

          if !cached && pending.length >= capacity
            return CandidateScan.new(candidates: candidates, pending: pending, next_index: boundary,
                                     first_unresolved_index: unresolved || raw_index, overflowed: true)
          end

          seen[key]    = true
          candidates  << key
          pending     << key unless cached
          unresolved ||= raw_index unless cached
          boundary     = raw_index + 1
          counted     += 1 unless counting == :window_slots && cached && @cache[key].nil?

          break if need && counted >= need
        end

        CandidateScan.new(candidates: candidates, pending: pending, next_index: boundary,
                          first_unresolved_index: unresolved, overflowed: false)
      end

      # Continue from the unresolved suffix, serving every identity the cache
      # already answers and merging the store's answers back into the owner
      # sequence.
      def continued(association, repository, found, seen_targets, resolved_candidates, resolved_boundary, offset, required_count)
        consumed = resolved_candidates.to_h { |key| [key, true] }
        sequence = []
        db_ids   = []

        association.__owner_ids__[resolved_boundary..].to_a.each do |id|
          next if id.nil?

          key = repository.adapter.make_id(id)
          next if consumed[key]

          consumed[key] = true

          if @cache.key?(key)
            target = @cache[key]
            next if target.nil? || seen_targets[target._id]

            sequence << [:cache, key, target]
          else
            sequence << [:db, key, nil]
            db_ids   << id
          end
        end

        @progress[association.__owner__] = resolved_candidates.length

        needed   = required_count && required_count - found.length
        db_index = read_suffix(repository, db_ids, needed)

        remainder = []

        sequence.each do |kind, key, target|
          break if needed && remainder.length >= needed

          target = db_index[key] if kind == :db
          next if target.nil? || seen_targets[target._id]

          seen_targets[target._id] = true
          remainder << target
        end

        (found + remainder).drop(offset).map(&:dup)
      end

      def read_suffix(repository, db_ids, needed)
        return {} if db_ids.empty?

        reader  = suffix_repository(repository, db_ids)
        results = needed ? reader.all { offset(0).limit(needed) } : reader.all

        results.each_with_object({}) do |target, index|
          Array(target._id).compact.each do |component|
            index[repository.adapter.make_id(component)] = target
          end
        end
      end

      def suffix_repository(base, suffix_ids)
        base.dup.tap do |repository|
          repository.local_conditions[repository.k(:_id, :in)] = suffix_ids
          repository.id_order = suffix_ids
        end
      end

      def fetch(association, repository, pending, offset, limit, capacity)
        batch = pending

        if @looked_up
          batch = (pending + shared_pending(association, repository, offset, limit, capacity - pending.length)).uniq
        end

        @looked_up        = true
        @requested_count += batch.length

        batch.each_slice(BATCH_SIZE) do |slice|
          slice.each { |id| @cache[id] = nil }
          repository.all(repository.k(:_id, :in) => slice).each { |target| index(target) }
        end
      end

      # Other owners contribute their own window prefixes, resumed from
      # wherever their earlier reads stopped.
      def shared_pending(association, repository, offset, limit, capacity)
        shared = []

        @entries.each do |entry|
          break if shared.length >= capacity

          ids  = Array(entry[association.__target_key__])
          need = limit && @progress[entry] + offset + limit
          walk = walk_candidates(repository, ids, need, capacity - shared.length, counting: :window_slots)

          shared |= walk.pending
        end

        shared
      end

      # A synced target may be referenced by any of its identity components.
      def index(target)
        return if target.nil?

        Array(target._id).compact.each { |component| @cache[component] = target }
      end

      def base(association)
        @repository ||= association.__configured_repository__.dup
      end

      class Source < SimpleDelegator

        def initialize(preloader, association)
          super(nil)
          @preloader, @association = preloader, association
        end

        def load_window(conditions, offset, limit)
          return @preloader.targets_for(@association, offset || 0, limit) if conditions.blank?

          window_offset, window_limit = offset, limit

          __getobj__.all(conditions || {}) { offset(window_offset).limit(window_limit) }
        end

        def all(conditions = {}, &block)
          return __getobj__.all(conditions || {}, &block) if block || conditions.present?

          load_window(conditions, 0, nil)
        end

        def first(conditions = {}, &block)
          return __getobj__.first(conditions || {}, &block) if block || conditions.present?

          load_window(nil, 0, 1).first
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
