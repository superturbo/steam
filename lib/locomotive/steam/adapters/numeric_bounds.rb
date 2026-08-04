module Locomotive::Steam
  module Adapters

    # The numeric domain every store shares: BSON int64 and finite doubles.
    # Query operands, stored values and increments all answer to it.
    module NumericBounds

      INT64 = (-2**63..2**63 - 1).freeze

      private_constant :INT64

      module_function

      def within?(number)
        number.is_a?(Integer) ? INT64.cover?(number) : number.finite?
      end

      # Stored-value bounds that keep the increment inside the numeric domain.
      def room_for(amount)
        low, high = amount.is_a?(Integer) ? [INT64.first, INT64.last] : [-Float::MAX, Float::MAX]

        [[low - amount, low].max, [high - amount, high].min]
      end

    end
  end
end
