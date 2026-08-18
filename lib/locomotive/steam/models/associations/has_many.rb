module Locomotive::Steam
  module Models

    class HasManyAssociation < ReferencedAssociation

      def __load__
        return @preloader.source_for(self) if @preloader

        repository = __configured_repository__
        key        = repository.k(__inverse_key__, :in)

        # a synced owner may be referenced by either identity
        repository.local_conditions[key] = Array(@entity._id).compact

        # Preserve a runtime order override.
        repository.local_conditions[:order_by] ||= @options[:order_by] unless @options[:order_by].blank?

        repository
      end

      def __inverse_key__
        :"#{@options[:inverse_of]}_id"
      end

      def __declared_order__
        @options[:order_by]
      end

    end

  end
end
