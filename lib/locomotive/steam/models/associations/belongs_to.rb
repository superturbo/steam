module Locomotive::Steam
  module Models

    class BelongsToAssociation < ReferencedAssociation

      # Copies do not inherit the window preloader.
      def initialize_copy(source)
        super
        @preloader = nil
      end

      def __preload_from__(preloader)
        @preloader = preloader
      end

      def __load__
        # Resolving a key the store never held must not materialize either side.
        return unless @entity.attributes.key?(__target_key__)

        target_id = @entity[__target_key__]

        return @entity[__name__] = nil if target_id.nil?

        @entity[__name__] =
          @preloader ? @preloader.target_for(self, target_id) : __configured_repository__.find(target_id)
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
