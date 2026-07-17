require 'set'

module Locomotive::Steam
  module Adapters
    module Query

      # Neutral coercion and validation of a raw query value to its operator's
      # value kind. It never builds an engine-specific filter — it returns the
      # normalized value or raises InvalidValue. See docs/query_semantics.md.
      module Values

        module_function

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

        # in/nin/all take a list of scalars. A Set or a lone scalar is
        # normalized; a Range is rejected rather than enumerated, so a wide
        # range can't explode into a huge query. Every element must be a scalar
        # or nil — nested arrays, hashes, ranges, regexps and sets are rejected.
        def list(value)
          array =
            case value
            when Array then value.dup
            when Set   then value.to_a
            when Range then raise InvalidValue, "a Range is not allowed in a list operator: #{value.inspect}"
            else [value]
            end

          array.each do |element|
            case element
            when Array, Hash, Range, Regexp, Set
              raise InvalidValue, "a list value may contain only scalars or nil, got #{element.inspect}"
            end
          end

          array
        end

      end

    end
  end
end
