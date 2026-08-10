module Locomotive::Steam
  module Models

    class BelongsToAssociation < ReferencedAssociation

      def __load__
        # Resolving a key the store never held must not materialize either side.
        return unless @entity.attributes.key?(__target_key__)

        target_id = @entity[__target_key__]
        target    = @repository.find(target_id)

        # replace the proxy class by the real target entity
        @entity[__name__] = target
      end

      # Keep the existing id until the association is materialized or reassigned.
      def __serialize__(attributes)
        return unless attributes.key?(__name__)

        target = attributes.delete(__name__)

        attributes[__target_key__] = target.try(:_id) unless target.is_a?(ReferencedAssociation)
      end

      def __target_key__
        :"#{__name__}_id"
      end

    end

  end
end
