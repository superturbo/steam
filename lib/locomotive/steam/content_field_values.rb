require_relative 'adapters/numeric_bounds'

module Locomotive::Steam

  # Parses scalar field values without deciding how callers handle invalid input.
  module ContentFieldValues

    class ParseError < StandardError; end

    # Numeric strings accept decimal notation only.
    INTEGER_FORMAT = /\A[+-]?\d+\z/.freeze
    FLOAT_FORMAT   = /\A[+-]?(?:\d+(?:\.\d+)?|\.\d+)(?:[eE][+-]?\d+)?\z/.freeze

    private_constant :INTEGER_FORMAT, :FLOAT_FORMAT

    module_function

    def number(value, type)
      candidate = value.strip
      format    = type == :integer ? INTEGER_FORMAT : FLOAT_FORMAT

      raise ParseError, "expected a number, got #{value.inspect}" unless format.match?(candidate)

      parsed = type == :integer ? Integer(candidate, 10) : Float(candidate)

      unless Adapters::NumericBounds.within?(parsed)
        raise ParseError, "number outside supported bounds: #{value.inspect}"
      end

      parsed
    end

    def time(value)
      parsed = begin
        Time.zone.parse(value)
      rescue ArgumentError
        nil
      end

      parsed || raise(ParseError, "invalid date: #{value.inspect}")
    end

  end
end
