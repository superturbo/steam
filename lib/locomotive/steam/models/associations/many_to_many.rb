module Locomotive::Steam
  module Models

    class ManyToManyAssociation < ReferencedAssociation

      def __load__
        repository = __configured_repository__
        key        = repository.k(:_id, :in)

        repository.local_conditions[key] = @entity[__target_key__] || []

        # Preserve a runtime order override.
        repository.local_conditions[:order_by] ||= @options[:order_by] unless @options[:order_by].blank?

        repository
      end

      # Keep the existing ids until the association is materialized or reassigned.
      def __serialize__(attributes)
        return unless attributes.key?(__name__)

        targets = attributes.delete(__name__)

        attributes[__target_key__] = targets.try(:map, &:_id) unless targets.is_a?(ReferencedAssociation)
      end

      def __target_key__
        :"#{__name__.to_s.singularize}_ids"
      end


    end

  end
end
