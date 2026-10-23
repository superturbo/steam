module Locomotive::Steam
  module Models

    class BelongsToAssociation < ReferencedAssociation

      def __load__
        # Resolving a key the store never held must not materialize either side.
        return unless @entity.attributes.key?(__target_key__)

        target_id = @entity[__target_key__]

        # A read is no assignment: the stored id stays as it is.
        return @entity.attributes[__name__] = nil if target_id.nil?

        @entity.attributes[__name__] =
          @preloader ? @preloader.target_for(self, target_id) : __configured_repository__.find(target_id)
      end

      # Preserve stored IDs regardless of cached targets.
      def __serialize__(attributes)
        attributes.delete(__name__)
      end

      def __assigned__(name, value)
        if name == __name__
          return if value.is_a?(ReferencedAssociation)

          @entity.attributes[__target_key__] = ReferencedAssociation.stored_id(value.try(:_id))
        elsif name == __target_key__
          # Assigning an ID invalidates the cached target.
          @entity.attributes[__name__] = self
        end
      end

      def __target_key__
        :"#{__name__}_id"
      end

    end

  end
end
