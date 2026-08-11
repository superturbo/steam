require 'set'

module Locomotive::Steam
  module Adapters
    module Query

      # Neutral coercion and validation of a raw query value to its operator's
      # value kind. It never builds an engine-specific filter — it returns the
      # normalized value or raises InvalidValue. See docs/query_semantics.md.
      module Values

        VALUE_KINDS = %i(literal list all_list scalar boolean size range).freeze

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
        # because they carry their own plain-field semantics. Containers are
        # rebuilt rather than mutated — callers may reuse the criteria they
        # passed in.
        def literal(value)
          case value
          when Regexp, Range
            raise InvalidValue, "#{value.class} is only supported on a plain field: #{value.inspect}"
          when Array  then propagate_unmatchable(value.map { |element| literal(element) })
          when Set    then propagate_unmatchable(value.map { |element| literal(element) })
          when Hash   then propagate_unmatchable(literal_hash(value))
          when String, Symbol then readable_operand(value.to_s)
          else Comparison.normalize_scalar(value)
          end
        end

        # MongoDB compares embedded documents by key order, so the order is kept
        # and a collision created by stringifying keys is an error rather than a
        # silently dropped pair.
        def literal_hash(hash)
          hash.each_with_object({}) do |(key, value), result|
            name = readable_operand(key.to_s)

            return UNMATCHABLE if unmatchable?(name)

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
            text = readable_operand(value)

            raise InvalidValue, 'expected a boolean, got unreadable text' if unmatchable?(text)

            case text.downcase
            when 'true'  then return true
            when 'false' then return false
            end
          end

          raise InvalidValue, "expected a boolean, got #{value.inspect}"
        end

        INT32_MAX = 2**31 - 1

        private_constant :INT32_MAX

        # size accepts a non-negative int32 as an Integer or decimal string.
        def size(value)
          integer =
            case value
            when Integer then value
            when String  then readable_size(value)
            end

          unless integer.is_a?(Integer) && integer.between?(0, INT32_MAX)
            raise InvalidValue, "expected an array size between 0 and #{INT32_MAX}"
          end

          integer
        end

        # A plain-field Range must have at least one bound. Bounds read like
        # the scalar operands they stand for.
        def range(value)
          if value.begin.nil? && value.end.nil?
            raise InvalidValue, "a range needs at least one bound: #{value.inspect}"
          end

          lower = range_bound(value.begin)
          upper = range_bound(value.end)

          return UNMATCHABLE if unmatchable?(lower) || unmatchable?(upper)

          Range.new(lower, upper, value.exclude_end?)
        end

        # A unique value no stored field can equal.
        UNMATCHABLE = Object.new.freeze

        private_constant :UNMATCHABLE

        def unmatchable
          UNMATCHABLE
        end

        def unmatchable?(value)
          value.equal?(UNMATCHABLE)
        end

        # gt/gte/lt/lte operand: a single comparable value. Structures are
        # rejected because their ordering is not the same on both engines.
        # Booleans are ordered, false before true, the way both engines sort
        # them. Anything else Comparable passes through, so an ActiveSupport
        # time or a BSON id keeps working.
        def scalar(value)
          return value if unmatchable?(value)

          case value
          when nil                              then UNMATCHABLE
          when Array, Hash, Set, Range, Regexp  then raise InvalidValue, "#{value.class} cannot be compared: #{value.inspect}"
          when true, false                      then value
          when String, Symbol                   then readable_operand(value.to_s)
          when Comparable                       then Comparison.normalize_scalar(value)
          else raise InvalidValue, "value is not comparable: #{value.inspect}"
          end
        end

        # in/nin/all take a list. A lone value becomes a one-element list and a
        # Set becomes an Array; a Range is rejected rather than enumerated, so a
        # wide range can't explode into a huge query. Elements are normalized as
        # literals, which keeps nested arrays and embedded documents (both have
        # defined MongoDB semantics) and rejects Regexp and Range.
        def list(value)
          list_elements(value).reject { |element| unmatchable?(element) }
        end

        # all requires every element; one unmatchable element makes it unsatisfiable.
        def all_list(value)
          elements = list_elements(value)

          elements.any? { |element| unmatchable?(element) } ? UNMATCHABLE : elements
        end

        def list_elements(value)
          case value
          when Range then raise InvalidValue, "a Range is not allowed in a list operator: #{value.inspect}"
          when Array, Set then value.map { |element| literal(element) }
          else [literal(value)]
          end
        end

        # A container with an unmatchable element cannot match as a literal.
        def propagate_unmatchable(normalized)
          return normalized if unmatchable?(normalized)

          values = normalized.is_a?(Hash) ? normalized.values : normalized

          values.any? { |element| unmatchable?(element) } ? UNMATCHABLE : normalized
        end

        # Both stores hold UTF-8 text; an unreadable operand can never equal it.
        def readable_operand(value)
          Text.utf8(value) || UNMATCHABLE
        end

        def readable_size(value)
          text = readable_operand(value)

          Integer(text, 10) if !unmatchable?(text) && text.match?(/\A\d{1,10}\z/)
        end

        def range_bound(bound)
          case bound
          when String, Symbol then readable_operand(bound.to_s)
          else bound
          end
        end

        private_class_method :list_elements, :propagate_unmatchable, :readable_operand,
                             :readable_size, :range_bound

      end

    end
  end
end
