module Locomotive::Steam
  module Adapters

    # Normalize timestamps to BSON's UTC millisecond representation.
    module TimePrecision

      module_function

      def utc_ms(time = Time.current)
        utc = time.getutc
        utc.change(nsec: utc.nsec - utc.nsec % 1_000_000)
      end

    end
  end
end
