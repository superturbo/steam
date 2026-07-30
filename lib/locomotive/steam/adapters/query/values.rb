require 'set'

module Locomotive::Steam
  module Adapters
    module Query

      # Neutral coercion and validation of a raw query value to its operator's
      # value kind. It never builds an engine-specific filter — it returns the
      # normalized value or raises InvalidValue. See docs/query_semantics.md.
      module Values

        VALUE_KINDS = %i(literal list scalar boolean size range).freeze

        private_constant :VALUE_KINDS

        module_function

        # The one entry point both engines use, so a value kind can never mean
        # two different things.
        def coerce(kind, value)
          unless VALUE_KINDS.include?(kind)
            raise InvalidValue, "unknown value kind: #{kind.inspect}"
          end

          public_send(kind, value)
        end

        # A literal operand: scalars pass through, a Set becomes an Array and a
        # Hash gets String keys, both recursively. Regexp and Range are rejected
        # because they carry their own plain-field semantics. Always returns new
        # containers — callers may reuse the criteria they passed in.
        def literal(value)
          case value
          when Regexp, Range
            raise InvalidValue, "#{value.class} is only supported on a plain field: #{value.inspect}"
          when Array then value.map { |element| literal(element) }
          when Set   then value.map { |element| literal(element) }
          when Hash  then literal_hash(value)
          else value
          end
        end

        # MongoDB compares embedded documents by key order, so the order is kept
        # and a collision created by stringifying keys is an error rather than a
        # silently dropped pair.
        def literal_hash(hash)
          hash.each_with_object({}) do |(key, value), result|
            name = key.to_s

            if result.key?(name)
              raise InvalidValue, "duplicate key after normalization: #{name.inspect}"
            end

            result[name] = literal(value)
          end
        end

        private_class_method :literal_hash

        # exists takes a real boolean; the lenient yes/1/t forms are rejected.
        def boolean(value)
          return value if value.equal?(true) || value.equal?(false)

          if value.is_a?(String)
            case value.downcase
            when 'true'  then return true
            when 'false' then return false
            end
          end

          raise InvalidValue, "expected a boolean, got #{value.inspect}"
        end

        # size takes a non-negative integer; a plain decimal string is accepted.
        def size(value)
          integer =
            case value
            when Integer then value
            when String  then Integer(value, 10) if value.match?(/\A\d+\z/)
            end

          unless integer.is_a?(Integer) && integer >= 0
            raise InvalidValue, "expected a non-negative integer, got #{value.inspect}"
          end

          integer
        end

        # A plain-field Range must have at least one bound.
        def range(value)
          if value.begin.nil? && value.end.nil?
            raise InvalidValue, "a range needs at least one bound: #{value.inspect}"
          end

          value
        end

        # Marks a condition that can never match. Comparing against nothing is
        # not an error — a missing `params` value must render an empty list, not
        # a 500 — but it must mean the same on every engine, so the engines
        # translate this sentinel instead of passing nil to the driver.
        MATCH_NONE = Object.new.freeze

        private_constant :MATCH_NONE

        def match_none?(value)
          value.equal?(MATCH_NONE)
        end

        # gt/gte/lt/lte operand: a single comparable value. Structures are
        # rejected because their ordering is not the same on both engines, and
        # booleans because they are not Comparable in Ruby — ordering them has
        # no defined contract. Anything else Comparable passes through
        # untouched, so an ActiveSupport time or a BSON id keeps working.
        def scalar(value)
          case value
          when nil                              then MATCH_NONE
          when Array, Hash, Set, Range, Regexp  then raise InvalidValue, "#{value.class} cannot be compared: #{value.inspect}"
          when Comparable                       then value
          else raise InvalidValue, "value is not comparable: #{value.inspect}"
          end
        end

        # in/nin/all take a list. A lone value becomes a one-element list and a
        # Set becomes an Array; a Range is rejected rather than enumerated, so a
        # wide range can't explode into a huge query. Elements are normalized as
        # literals, which keeps nested arrays and embedded documents (both have
        # defined MongoDB semantics) and rejects Regexp and Range.
        def list(value)
          case value
          when Range then raise InvalidValue, "a Range is not allowed in a list operator: #{value.inspect}"
          when Array, Set then value.map { |element| literal(element) }
          else [literal(value)]
          end
        end

      end

    end
  end
end
