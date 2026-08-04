require_relative 'adapters/numeric_bounds'

module Locomotive::Steam

  # Parses scalar field values without deciding how callers handle invalid input.
  module ContentFieldValues

    class ParseError < StandardError; end

    # Numeric strings accept decimal notation only.
    INTEGER_FORMAT = /\A[+-]?\d+\z/.freeze
    FLOAT_FORMAT   = /\A[+-]?(?:\d+(?:\.\d+)?|\.\d+)(?:[eE][+-]?\d+)?\z/.freeze

    # A calendar date takes either separator; a date and time takes ISO 8601,
    # with or without an offset.
    DASH_DATE  = /\A\d{4}-\d{2}-\d{2}\z/.freeze
    SLASH_DATE = %r{\A\d{4}/\d{2}/\d{2}\z}.freeze
    ISO_TIME   = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:?\d{2})?\z/.freeze

    BOOLEANS = { true => true, false => false, 'true' => true, 'false' => false,
                 '1' => true, '0' => false }.freeze

    private_constant :INTEGER_FORMAT, :FLOAT_FORMAT, :DASH_DATE, :SLASH_DATE, :ISO_TIME, :BOOLEANS

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

    def date(value)
      candidate = value.strip

      unless DASH_DATE.match?(candidate) || SLASH_DATE.match?(candidate)
        raise ParseError, "invalid date: #{value.inspect}"
      end

      begin
        Date.strptime(candidate, candidate.include?('/') ? '%Y/%m/%d' : '%Y-%m-%d')
      rescue ArgumentError
        raise ParseError, "invalid date: #{value.inspect}"
      end
    end

    # A date on its own resolves to midnight in the current zone; an offset the
    # value carries decides the instant on its own.
    def date_time(value)
      candidate = value.strip

      unless DASH_DATE.match?(candidate) || ISO_TIME.match?(candidate)
        raise ParseError, "invalid date: #{value.inspect}"
      end

      parsed = begin
        Time.zone.parse(candidate)
      rescue ArgumentError
        nil
      end

      parsed || raise(ParseError, "invalid date: #{value.inspect}")
    end

    def boolean(value)
      key = value.is_a?(String) ? value.strip.downcase : value

      BOOLEANS.fetch(key) { raise ParseError, "expected a boolean, got #{value.inspect}" }
    end

  end
end
