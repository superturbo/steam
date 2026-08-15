module Locomotive::Steam
  module Models

    class ReferencedAssociation

      attr_reader :repository

      # Copies do not inherit the window preloader.
      def initialize_copy(source)
        super
        @repository = source.repository.dup
        @preloader  = nil
      end

      def __preload_from__(preloader)
        @preloader = preloader
      end

      def initialize(repository_klass, scope, adapter, options = {}, &block)
        @repository = repository_klass.new(adapter)

        # A locale change on the parent repository does not reach this copy.
        @repository.scope = scope.dup

        @configure_repository = block

        @options = options
      end

      def __name__
        @options[:association_name]
      end

      def __attach__(entity)
        @entity = entity
      end

      def __load__
      end

      def __serialize__(entity)
      end

      def __configured_repository__
        if @configure_repository
          @configure_repository.call(@repository, @options)
          @configure_repository = nil
        end

        @repository
      end

      def method_missing(name, *args, &block)
        __load__.try(:send, name, *args, &block)
      end

    end

  end
end
