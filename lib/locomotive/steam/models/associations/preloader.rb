module Locomotive::Steam
  module Models

    # Lazily batches belongs_to reads within one bounded window.
    class AssociationPreloader

      # Keep $in batches below the measured planner crossover.
      BATCH_SIZE = 100

      private_constant :BATCH_SIZE

      def self.attach(entries)
        preloader = new(entries)

        entries.each do |entry|
          next unless entry.respond_to?(:associations)

          (entry.associations || {}).each_value do |association|
            association.__preload_from__(preloader) if association.is_a?(BelongsToAssociation)
          end
        end
      end

      def initialize(entries)
        @entries      = entries
        @repositories = {}
        @caches       = {}
        @looked_up    = {}
      end

      # A cached nil is an answer: the target is absent or hidden.
      def target_for(association, id)
        name       = association.__name__
        repository = (@repositories[name] ||= association.__configured_repository__)
        cache      = (@caches[name] ||= {})
        key        = repository.adapter.make_id(id)

        fetch(association, repository, cache, key) unless cache.key?(key)

        cache[key]&.dup
      end

      private

      def fetch(association, repository, cache, key)
        if @looked_up[association.__name__]
          batch = batch_around(repository, cache, key, association.__target_key__)
          batch.each { |batch_key| cache[batch_key] = nil }
          repository.all(repository.k(:_id, :in) => batch).each { |target| index(cache, target) }
        else
          @looked_up[association.__name__] = true
          cache[key] = nil
          index(cache, repository.find(key))
        end
      end

      # A synced target may be referenced by any of its identity components.
      def index(cache, target)
        return if target.nil?

        Array(target._id).compact.each { |component| cache[component] = target }
      end

      def batch_around(repository, cache, key, target_key)
        pending = @entries.filter_map { |entry| entry[target_key] }
                          .map { |id| repository.adapter.make_id(id) }.uniq
                          .reject { |pending_key| cache.key?(pending_key) }

        pending.each_slice(BATCH_SIZE).find { |batch| batch.include?(key) } || [key]
      end

    end

  end
end
