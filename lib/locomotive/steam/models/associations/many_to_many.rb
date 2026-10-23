module Locomotive::Steam
  module Models

    class ManyToManyAssociation < ReferencedAssociation

      def __load__
        return @preloader.source_for(self) if @preloader && @options[:order_by].blank?

        repository = __configured_repository__
        ids        = __owner_ids__

        # The ID filter serves every operation; enumeration also preserves its order.
        repository.local_conditions[repository.k(:_id, :in)] = ids

        if @options[:order_by].blank?
          repository.id_order = ids
        else
          repository.local_conditions[:order_by] ||= @options[:order_by]
        end

        repository
      end

      def __owner_ids__
        Array(@entity[__target_key__])
      end

      # Preserve stored IDs regardless of cached targets.
      def __serialize__(attributes)
        attributes.delete(__name__)
      end

      def __assigned__(name, value)
        if name == __name__
          return if value.is_a?(ReferencedAssociation)

          @entity.attributes[__target_key__] = value.try(:map) { |target| ReferencedAssociation.stored_id(target._id) }
        elsif name == __target_key__
          # Assigning an ID invalidates the cached targets.
          @entity.attributes[__name__] = self
        end
      end

      def __target_key__
        :"#{__name__.to_s.singularize}_ids"
      end


    end

  end
end
