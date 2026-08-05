module Locomotive::Steam
  module Models

    # A value a caller may change without changing the one a store keeps.
    module Copy

      module_function

      def of(value)
        case value
        when ::String then value.dup
        when ::Array  then value.map { |item| of(item) }
        when ::Hash   then hash(value)
        else value
        end
      end

      def hash(value)
        value.each_with_object(value.dup) { |(name, item), copy| copy[name] = of(item) }
          .tap { |copy| copy.default = of(copy.default) unless copy.default.nil? }
      end

    end

  end
end
