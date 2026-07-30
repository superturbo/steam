require_relative '../query'

module Locomotive::Steam
  module Adapters
    module Memory

      class Condition

        LIST_OPERATORS = %i(in nin all).freeze

        attr_reader :field, :operator, :value

        def initialize(operator_and_field, value, locale)
          @locale = locale.try(:to_sym)
          @operator_and_field, @value = operator_and_field, value
          @operator, @field = :==, operator_and_field

          decode_operator_and_field!
          normalize_value!
        end

        def matches?(entry)
          present, value = read(entry)

          case @operator
          when :==, :eq   then eq_match?(value)
          when :ne        then !eq_match?(value)
          when :in        then in_match?(value)
          when :nin       then !in_match?(value)
          when :all       then all_match?(value)
          when :exists    then present == @exists
          when :matches   then regexp_match?(value)
          when :range     then range_match?(value)
          when :gt        then compare(value) { |order| order > 0 }
          when :gte       then compare(value) { |order| order >= 0 }
          when :lt        then compare(value) { |order| order < 0 }
          when :lte       then compare(value) { |order| order <= 0 }
          when :size      then value.is_a?(Array) && value.size == @size
          else
            raise Adapters::Query::UnsupportedOperator,
                  "#{@operator} is unknown or not implemented."
          end
        end

        def inspect
          "#{field}#{operator != :== ? '.' : ' '}#{operator} #{value.inspect}"
        end

        protected

        def decode_operator_and_field!
          field, operator = Adapters::Query::Operators.decode(@operator_and_field)

          if operator
            @field, @operator = field.to_sym, operator.name
          elsif @value.is_a?(Regexp)
            @operator = :matches
          elsif @value.is_a?(Range)
            @operator = :range
          end
        end

        def normalize_value!
          values = Adapters::Query::Values

          case @operator
          when *LIST_OPERATORS then @list    = values.coerce(:list, @value)
          when :exists         then @exists  = values.coerce(:boolean, @value)
          when :size           then @size    = values.coerce(:size, @value)
          when :range          then @range   = values.coerce(:range, @value)
          when :==, :eq, :ne   then @literal = values.coerce(:literal, @value)
          when :gt, :gte, :lt, :lte then @scalar = values.coerce(:scalar, @value)
          end
        end

        # Preserve missing vs null for MongoDB parity.
        def read(entry)
          return [false, nil] unless entry.respond_to?(@field)

          value = entry.public_send(@field)

          if value.respond_to?(:translations)
            [value.translations.key?(@locale), value[@locale]]
          else
            [true, value]
          end
        end

        private

        # Comparisons go through <=> so a missing field or a value of another
        # type is simply no match: incompatible values do not match under
        # MongoDB type bracketing either. An array field matches when one of its
        # elements does.
        def compare(value, operand = @scalar)
          return false if Adapters::Query::Values.match_none?(operand)

          elements(value).any? do |candidate|
            order = candidate <=> operand

            order.nil? ? false : yield(order)
          end
        end

        # Different array elements may satisfy a Range's bounds.
        def range_match?(value)
          from, to = @range.begin, @range.end

          (from.nil? || compare(value, from) { |order| order >= 0 }) &&
            (to.nil? || compare(value, to) { |order| @range.exclude_end? ? order < 0 : order <= 0 })
        end

        def elements(value)
          value.is_a?(Array) ? value : [value]
        end

        # A query on a field matches the whole stored value or, when that value
        # is an array, any of its direct elements — MongoDB's candidate model.
        def candidates(value)
          value.is_a?(Array) ? [value, *value] : [value]
        end

        def eq_match?(value)
          candidates(value).any? { |candidate| same?(candidate, @literal) }
        end

        # MongoDB applies a regexp to string values only, array elements included.
        def regexp_match?(value)
          elements(value).any? { |candidate| candidate.is_a?(String) && @value.match?(candidate) }
        end

        def in_match?(value)
          candidates(value).any? { |candidate| @list.any? { |operand| same?(candidate, operand) } }
        end

        def all_match?(value)
          return false if @list.empty?

          field_candidates = candidates(value)
          @list.all? { |operand| field_candidates.any? { |candidate| same?(candidate, operand) } }
        end

        # MongoDB compares embedded documents by key order, which Ruby's Hash#==
        # ignores, so equality is walked explicitly.
        def same?(stored, operand)
          if operand.is_a?(Hash) && stored.is_a?(Hash)
            stored.size == operand.size &&
              stored.to_a.zip(operand.to_a).all? { |(sk, sv), (ok, ov)| sk.to_s == ok.to_s && same?(sv, ov) }
          elsif operand.is_a?(Array) && stored.is_a?(Array)
            stored.size == operand.size &&
              stored.zip(operand).all? { |element, other| same?(element, other) }
          else
            stored == operand
          end
        end

      end

    end
  end
end
