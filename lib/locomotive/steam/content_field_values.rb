require_relative 'adapters/numeric_bounds'

module Locomotive::Steam

  # Normalizes content field values independently of their storage adapter.
  module ContentFieldValues

    class ParseError < StandardError; end
    class ConfigurationError < StandardError; end

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

    # A date on its own resolves to midnight in the zone it is given; an offset
    # the value carries decides the instant on its own.
    def date_time(value, zone)
      candidate = value.strip

      unless DASH_DATE.match?(candidate) || ISO_TIME.match?(candidate)
        raise ParseError, "invalid date: #{value.inspect}"
      end

      parsed = begin
        zone.parse(candidate)
      rescue ArgumentError
        nil
      end

      parsed || raise(ParseError, "invalid date: #{value.inspect}")
    end

    # A value the grammar cannot read is left exactly as it is.
    def deserialize(type, value, zone)
      case type
      when :date      then stored_date(value)
      when :date_time then stored_date_time(value, zone)
      else value
      end
    end

    def stored_date(value)
      return date(value) if value.is_a?(String)
      return value if plain_date?(value)
      return value.to_time.getutc.to_date if value.respond_to?(:to_time)

      value
    rescue ParseError
      value
    end

    def stored_date_time(value, zone)
      return date_time(value, zone).getutc if value.is_a?(String)
      return date_at_midnight(value, zone) if plain_date?(value)
      return value.to_time.getutc if value.respond_to?(:to_time)

      value
    rescue ParseError
      value
    end

    def plain_date?(value)
      value.is_a?(Date) && !value.is_a?(DateTime)
    end

    # A calendar date names a day, not an instant: the zone decides which.
    def date_at_midnight(value, zone)
      zone.local(value.year, value.month, value.day).getutc
    end

    STORED_DIFFERENTLY = %i(date date_time).freeze

    private_constant :STORED_DIFFERENTLY

    # Preserve missing fields and resolve the timezone only when needed.
    def deserialize_entry(entity)
      zone = nil

      entity.content_type.fields_by_name.each_value do |field|
        next unless STORED_DIFFERENTLY.include?(field.type)

        name = field.persisted_name
        next unless name && entity.attributes.key?(name)

        zone ||= zone_of(entity.site) if field.type == :date_time

        entity.attributes[name] = deserialize_attribute(field.type, entity.attributes[name], zone)
      end

      entity
    end

    # Preserve scalar fallbacks and absent translations.
    def deserialize_attribute(type, value, zone)
      return deserialize(type, value, zone) unless value.respond_to?(:translations)

      value.apply { |translated| deserialize(type, translated, zone) }
    end

    def zone_of(site)
      raise ConfigurationError, 'a site timezone is required to read a date-time value' if site.nil?

      site.timezone ||
        raise(ConfigurationError, "unknown timezone: #{site.timezone_name.inspect}")
    end

    def boolean(value)
      key = value.is_a?(String) ? value.strip.downcase : value

      BOOLEANS.fetch(key) { raise ParseError, "expected a boolean, got #{value.inspect}" }
    end

  end
end
