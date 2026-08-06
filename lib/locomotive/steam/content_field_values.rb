require 'json'

require_relative 'adapters/numeric_bounds'

module Locomotive::Steam

  # Normalizes content field values independently of their storage adapter.
  module ContentFieldValues

    # Reasons are stable identifiers; messages never include rejected values.
    class ParseError < StandardError

      REASONS = %i(invalid_boolean invalid_date invalid_encoding invalid_json
                   invalid_json_name invalid_json_value invalid_number
                   invalid_password_hash json_too_deep outside_numeric_bounds
                   wrong_stored_type wrong_type).freeze

      attr_reader :reason

      def initialize(reason, message)
        raise ArgumentError, "no such parse error reason: #{reason.inspect}" unless REASONS.include?(reason)

        @reason = reason

        super(message)
      end

    end

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

    # MongoDB's limit includes the document and localized field container.
    MAX_JSON_DEPTH = 98

    private_constant :INTEGER_FORMAT, :FLOAT_FORMAT, :DASH_DATE, :SLASH_DATE, :ISO_TIME,
                     :BOOLEANS, :MAX_JSON_DEPTH

    module_function

    def number(value, type)
      candidate = value.strip
      format    = type == :integer ? INTEGER_FORMAT : FLOAT_FORMAT

      raise ParseError.new(:invalid_number, "invalid #{type} value") unless format.match?(candidate)

      parsed = type == :integer ? Integer(candidate, 10) : Float(candidate)

      unless Adapters::NumericBounds.within?(parsed)
        raise ParseError.new(:outside_numeric_bounds, 'number outside supported bounds')
      end

      parsed
    end

    def date(value)
      candidate = value.strip

      unless DASH_DATE.match?(candidate) || SLASH_DATE.match?(candidate)
        raise ParseError.new(:invalid_date, 'invalid date value')
      end

      begin
        Date.strptime(candidate, candidate.include?('/') ? '%Y/%m/%d' : '%Y-%m-%d')
      rescue ArgumentError
        raise ParseError.new(:invalid_date, 'invalid date value')
      end
    end

    # A date on its own resolves to midnight in the zone it is given; an offset
    # the value carries decides the instant on its own.
    def date_time(value, zone)
      candidate = value.strip

      unless DASH_DATE.match?(candidate) || ISO_TIME.match?(candidate)
        raise ParseError.new(:invalid_date, 'invalid date and time value')
      end

      parsed = begin
        zone.parse(candidate)
      rescue ArgumentError
        nil
      end

      parsed || raise(ParseError.new(:invalid_date, 'invalid date and time value'))
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

    # Normalizes caller input; stored values use #deserialize.
    def normalize_input(type, value, site = nil)
      return value if value.nil?

      value = readable_text(value) if value.is_a?(String)

      case type
      when :integer, :float               then input_number(value, type)
      when :boolean                       then blank_text?(value) ? nil : boolean(value)
      when :date                          then input_date(value, site)
      when :date_time                     then input_date_time(value, site)
      when :json                          then input_json(value)
      when :string, :text, :email, :color then input_string(value)
      else value
      end
    end

    # Validates adapter-decoded values without parsing stored text.
    def normalize_read(type, value)
      return value if value.nil?

      case type
      when :integer                       then read_number(value, Integer, 'an integer')
      when :float                         then read_number(value, Float, 'a float')
      when :boolean                       then read_boolean(value)
      when :date                          then read_date(value)
      when :date_time                     then read_date_time(value)
      when :json                          then read_json(value)
      when :string, :text, :email, :color then read_text(value)
      else value
      end
    end

    def read_number(value, wanted, expected)
      wrong_stored_type!(expected, value) unless value.instance_of?(wanted)
      return value if Adapters::NumericBounds.within?(value)

      raise ParseError.new(:outside_numeric_bounds, 'number outside supported bounds')
    end

    def read_boolean(value)
      return value if value.equal?(true) || value.equal?(false)

      wrong_stored_type!('a boolean', value)
    end

    def read_date(value)
      return value if plain_date?(value)

      wrong_stored_type!('a day', value)
    end

    def read_date_time(value)
      return value.getutc if value.instance_of?(Time)

      wrong_stored_type!('a moment', value)
    end

    def read_json(value)
      wrong_stored_type!('a JSON object', value) unless value.is_a?(Hash)

      json_value(value, 1)
    end

    def read_text(value)
      wrong_stored_type!('text', value) unless value.is_a?(String)

      readable_text(value)
    end

    def wrong_stored_type!(expected, value)
      raise ParseError.new(:wrong_stored_type, "expected #{expected} in the store, got #{value.class}")
    end

    def input_number(value, type)
      return nil if blank_text?(value)
      return number(value, type) if value.is_a?(String)

      wanted = type == :integer ? Integer : Float
      parsed = wanted == Float && value.is_a?(Integer) ? value.to_f : value

      unless parsed.instance_of?(wanted)
        raise ParseError.new(:wrong_type, "expected #{type}, got #{value.class}")
      end

      unless Adapters::NumericBounds.within?(parsed)
        raise ParseError.new(:outside_numeric_bounds, 'number outside supported bounds')
      end

      parsed
    end

    # A moment names the day it falls on where the site stands, which is not
    # always the day it falls on in UTC.
    def input_date(value, site)
      return nil if blank_text?(value)
      return date(value) if value.is_a?(String)
      return value if plain_date?(value)
      return value.to_time.in_time_zone(zone_of(site)).to_date if value.respond_to?(:to_time)

      raise ParseError.new(:wrong_type, "expected a date, got #{value.class}")
    end

    def input_date_time(value, site)
      return nil if blank_text?(value)
      return date_time(value, zone_of(site)).getutc if value.is_a?(String)
      return date_at_midnight(value, zone_of(site)) if plain_date?(value)
      return value.to_time.getutc if value.respond_to?(:to_time)

      raise ParseError.new(:wrong_type, "expected a date and time, got #{value.class}")
    end

    def input_json(value)
      return nil if blank_text?(value)

      object = value.is_a?(String) ? parse_json(value) : value

      unless object.is_a?(Hash)
        raise ParseError.new(:wrong_type, "expected a JSON object, got #{object.class}")
      end

      json_value(object, 1)
    end

    def parse_json(value)
      JSON.parse(value.strip, max_nesting: MAX_JSON_DEPTH,
                              allow_comments: false, allow_duplicate_key: false)
    rescue JSON::ParserError
      raise ParseError.new(:invalid_json, 'invalid JSON')
    end

    def json_value(value, depth)
      case value
      when Hash                     then json_hash(value, depth)
      when Array                    then json_array(value, depth)
      when String                   then readable_text(value)
      when true, false, nil         then value
      when Integer, Float           then json_number(value)
      else raise ParseError.new(:invalid_json_value, "a #{value.class} cannot be stored as JSON")
      end
    end

    def json_hash(hash, depth)
      guard_depth(depth)

      hash.each_with_object({}) do |(key, value), object|
        object[json_key(key)] = json_value(value, depth + 1)
      end
    end

    def json_array(array, depth)
      guard_depth(depth)

      array.map { |item| json_value(item, depth + 1) }
    end

    def guard_depth(depth)
      return if depth <= MAX_JSON_DEPTH

      raise ParseError.new(:json_too_deep, "JSON nested deeper than #{MAX_JSON_DEPTH}")
    end

    def json_key(key)
      unless key.is_a?(String) || key.is_a?(Symbol)
        raise ParseError.new(:invalid_json_name, "a #{key.class} cannot name a JSON value")
      end

      name = readable_text(key.to_s)

      # BSON field names cannot contain a null character.
      if name.include?("\u0000")
        raise ParseError.new(:invalid_json_name, 'a JSON name cannot hold a null character')
      end

      name
    end

    def json_number(value)
      return value if Adapters::NumericBounds.within?(value)

      raise ParseError.new(:outside_numeric_bounds, 'number outside supported bounds')
    end

    # Both adapters store text as UTF-8.
    def readable_text(value)
      raise ParseError.new(:invalid_encoding, 'text in no readable encoding') unless value.valid_encoding?

      value.encode(Encoding::UTF_8)
    rescue EncodingError
      raise ParseError.new(:invalid_encoding, 'text no store can keep')
    end

    def input_string(value)
      return value if value.is_a?(String)

      raise ParseError.new(:wrong_type, "expected text, got #{value.class}")
    end

    def blank_text?(value)
      value.is_a?(String) && value.strip.empty?
    end

    private_class_method :input_json, :parse_json, :json_value, :json_hash, :json_array,
                         :guard_depth, :json_key, :json_number, :readable_text,
                         :read_number, :read_boolean, :read_date, :read_date_time,
                         :read_json, :read_text, :wrong_stored_type!

    def zone_of(site)
      raise ConfigurationError, 'a site timezone is required to read this value' if site.nil?

      site.timezone ||
        raise(ConfigurationError, "unknown timezone: #{site.timezone_name.inspect}")
    end

    # Invalid boolean text breaks the grammar; other objects have the wrong type.
    def boolean(value)
      key = value.is_a?(String) ? value.strip.downcase : value

      BOOLEANS.fetch(key) do
        raise ParseError.new(:invalid_boolean, 'invalid boolean value') if value.is_a?(String)

        raise ParseError.new(:wrong_type, "expected a boolean, got #{value.class}")
      end
    end

  end
end
