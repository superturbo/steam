module Locomotive::Steam
  module Models

    class HasManyAssociation < ReferencedAssociation

      def __load__
        key = @repository.k(:"#{@options[:inverse_of]}_id", :in)

        # a synced owner may be referenced by either identity
        @repository.local_conditions[key] = Array(@entity._id).compact

        # use order_by from options as the default one for further queries
        @repository.local_conditions[:order_by] = @options[:order_by] unless @options[:order_by].blank?

        # all the further calls (method_missing) will be delegated to @repository
        @repository
      end

    end

  end
end
