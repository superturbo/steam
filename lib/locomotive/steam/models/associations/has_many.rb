module Locomotive::Steam
  module Models

    class HasManyAssociation < ReferencedAssociation

      def __load__
        repository = __configured_repository__
        key        = repository.k(:"#{@options[:inverse_of]}_id", :in)

        # a synced owner may be referenced by either identity
        repository.local_conditions[key] = Array(@entity._id).compact

        # Preserve a runtime order override.
        repository.local_conditions[:order_by] ||= @options[:order_by] unless @options[:order_by].blank?

        repository
      end

    end

  end
end
