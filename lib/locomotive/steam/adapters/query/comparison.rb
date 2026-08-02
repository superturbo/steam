module Locomotive::Steam
  module Adapters
    module Query

      module Comparison

        BOOLEANS = { false => 0, true => 1 }.freeze

        private_constant :BOOLEANS

        module_function

        # A Symbol names the string it spells, on the stored side too.
        def normalize_scalar(value)
          value.is_a?(Symbol) ? value.to_s : value
        end

        # Incomparable values have no order; what that means is the caller's.
        def compare(one, other)
          one, other = normalize_scalar(one), normalize_scalar(other)

          return BOOLEANS[one] <=> BOOLEANS[other] if BOOLEANS.key?(one) && BOOLEANS.key?(other)

          one <=> other
        end

      end

    end
  end
end
