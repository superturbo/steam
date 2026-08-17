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

      def __owner__
        @entity
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
