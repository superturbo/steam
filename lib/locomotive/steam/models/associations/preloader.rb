module Locomotive::Steam
  module Models

    # Coordinates association preloaders within one bounded window. One
    # window holds entries of one site, content type and locale; every
    # strategy relies on that.
    class AssociationPreloader

      PRELOADERS = {
        BelongsToAssociation  => BelongsToPreloader,
        ManyToManyAssociation => ManyToManyPreloader,
        HasManyAssociation    => HasManyPreloader
      }.freeze

      private_constant :PRELOADERS

      def self.attach(entries)
        preloader = new(entries)

        entries.each do |entry|
          next unless entry.respond_to?(:associations)

          (entry.associations || {}).each_value do |association|
            association.__preload_from__(preloader) if preloader.handles?(association)
          end
        end
      end

      def initialize(entries)
        @entries    = entries
        @preloaders = {}
      end

      def target_for(association, id)
        preloader_for(association).target_for(association, id)
      end

      def source_for(association)
        preloader_for(association).source_for(association)
      end

      def handles?(association)
        !preloader_class(association).nil?
      end

      private

      def preloader_class(association)
        PRELOADERS.each { |klass, preloader| return preloader if association.is_a?(klass) }

        nil
      end

      def preloader_for(association)
        @preloaders[association.__name__] ||= preloader_class(association).new(@entries)
      end

    end

  end
end
