module Locomotive::Steam
  module Models

    # One foreign key per owner: the first unique link costs a find, the
    # next one loads its batch, untouched batches are never read.
    class BelongsToPreloader

      # Keep $in batches below the measured planner crossover.
      BATCH_SIZE = 100

      private_constant :BATCH_SIZE

      def initialize(entries)
        @entries   = entries
        @cache     = {}
        @looked_up = false
      end

      # A cached nil is an answer: the target is absent or hidden.
      def target_for(association, id)
        repository = (@repository ||= association.__configured_repository__)
        key        = repository.adapter.make_id(id)

        fetch(association, repository, key) unless @cache.key?(key)

        @cache[key]&.dup
      end

      private

      def fetch(association, repository, key)
        if @looked_up
          batch = batch_around(repository, key, association.__target_key__)
          batch.each { |batch_key| @cache[batch_key] = nil }
          repository.all(repository.k(:_id, :in) => batch).each { |target| index(target) }
        else
          @looked_up   = true
          @cache[key]  = nil
          index(repository.find(key))
        end
      end

      # A synced target may be referenced by any of its identity components.
      def index(target)
        return if target.nil?

        Array(target._id).compact.each { |component| @cache[component] = target }
      end

      def batch_around(repository, key, target_key)
        pending = @entries.filter_map { |entry| entry[target_key] }
                          .map { |id| repository.adapter.make_id(id) }.uniq
                          .reject { |pending_key| @cache.key?(pending_key) }

        pending.each_slice(BATCH_SIZE).find { |batch| batch.include?(key) } || [key]
      end

    end

  end
end
