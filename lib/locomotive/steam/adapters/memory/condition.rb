require_relative '../query'

module Locomotive::Steam
  module Adapters
    module Memory

      class Condition

        class UnsupportedOperator < StandardError; end

        OPERATORS      = %i(== eq ne neq matches gt gte lt lte size all in nin).freeze
        LIST_OPERATORS = %i(in nin all).freeze

        attr_reader :field, :operator, :value

        def initialize(operator_and_field, value, locale)
          @locale = locale.try(:to_sym)
          @operator_and_field, @value = operator_and_field, value
          @operator, @field = :==, operator_and_field

          decode_operator_and_field!

          @list = Adapters::Query::Values.list(@value) if LIST_OPERATORS.include?(@operator)
        end

        def matches?(entry)
          present, value = read(entry)

          case @operator
          when :==, :eq   then eq_match?(value)
          when :ne, :neq  then !eq_match?(value)
          when :in        then in_match?(value)
          when :nin       then !present || !in_match?(value)
          when :all       then all_match?(value)
          when :matches   then !(@value =~ value).nil?
          when :gt        then value && value > @value
          when :gte       then value && value >= @value
          when :lt        then value && value < @value
          when :lte       then value && value <= @value
          when :size      then value.size == @value
          else
            raise UnsupportedOperator.new("#{@operator} is unknown or not implemented.")
          end
        end

        def inspect
          "#{field}#{operator != :== ? '.' : ' '}#{operator} #{value.inspect}"
        end

        protected

        def decode_operator_and_field!
          if match = @operator_and_field.match(/^(?<field>[a-z0-9_-]+)\.(?<operator>.*)$/)
            @field    = match[:field].to_sym
            @operator = match[:operator].to_sym
            check_operator!
          elsif @value.is_a?(Regexp)
            @operator = :matches
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

        # MongoDB equality matches scalar array elements, but arrays exactly.
        def eq_match?(value)
          if @value.is_a?(Array)
            value == @value
          elsif value.is_a?(Array)
            value.include?(@value)
          else
            value == @value
          end
        end

        def in_match?(value)
          value.is_a?(Array) ? value.intersect?(@list) : @list.include?(value)
        end

        def all_match?(value)
          return false if @list.empty?

          value.is_a?(Array) ? (@list - value).empty? : @list == [value]
        end

        def check_operator!
          raise UnsupportedOperator.new unless OPERATORS.include?(@operator)
        end

      end

    end
  end
end
