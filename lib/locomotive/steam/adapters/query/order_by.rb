module Locomotive::Steam
  module Adapters
    module Query

      # Normalizes order_by to [[:field, :asc|:desc], ...].
      module OrderBy

        DIRECTIONS = { 'asc' => :asc, 'desc' => :desc }.freeze

        module_function

        def decode(*spec)
          return [pair(*spec)] if positional_pair?(spec)

          validate_unique_fields!(spec.flat_map { |criterion| criteria(criterion) })
        end

        # Mongo compiles the sequence into a Hash, so a second direction for a
        # field would replace the first while Memory keeps both.
        def validate_unique_fields!(criteria)
          seen = {}

          criteria.each do |field, _|
            raise InvalidValue, "duplicate order field: #{field.inspect}" if seen.key?(field)

            seen[field] = true
          end

          criteria
        end

        private_class_method :validate_unique_fields!

        def positional_pair?(spec)
          spec.size == 2 && spec.all? { |element| element.is_a?(Symbol) }
        end

        def criteria(criterion)
          case criterion
          when nil    then []
          when Symbol then [pair(criterion)]
          when Hash   then criterion.map { |field, direction| pair(field, direction) }
          when String then split_criteria(criterion)
          when Array  then array_criteria(criterion)
          else raise InvalidValue, "unsupported order_by: #{criterion.inspect}"
          end
        end

        # A flat array is a list of scalar criteria; a nested array is a list
        # whose sub-arrays are [field, direction] pairs.
        def array_criteria(criterion)
          return [] if criterion.empty?

          if scalar_list?(criterion)
            criterion.flat_map { |element| criteria(element) }
          else
            criterion.flat_map { |element| nested_criterion(element) }
          end
        end

        def nested_criterion(element)
          return criteria(element) unless element.is_a?(Array) && scalar_list?(element)

          if element.size > 2
            raise InvalidValue, "an order_by pair takes a field and an optional direction, got #{element.inspect}"
          end

          [pair(*element)]
        end

        def scalar_list?(array)
          array.none? { |element| element.is_a?(Array) || element.is_a?(Hash) }
        end

        def split_criteria(criterion)
          criterion = readable!(criterion, 'an order_by criterion must be readable text')

          criterion.split(',').map { |part| parse(part) }
        end

        def parse(part)
          tokens = part.strip.split(/[\s.|]+/)

          if tokens.length > 2
            raise InvalidValue, "an order_by criterion takes a field and an optional direction, got #{part.inspect}"
          end

          pair(*tokens)
        end

        def pair(field = nil, direction = nil)
          name = field.to_s
          raise InvalidValue, "order_by needs a field name, got #{field.inspect}" if name.empty?

          name = readable!(name, 'an order field must be readable text')

          if operator_field?(name)
            raise UnsupportedOperator, "order field may not contain a Mongo operator: #{name.inspect}"
          end

          [name.to_sym, direction(direction)]
        end

        def direction(value)
          case value
          when nil, 1 then :asc
          when -1     then :desc
          else
            name = readable!(value.to_s, 'an order direction must be readable text')

            DIRECTIONS.fetch(name.downcase) do
              raise InvalidValue, "unsupported order direction: #{value.inspect}"
            end
          end
        end

        def readable!(value, message)
          Text.utf8(value) || raise(InvalidValue, message)
        end

        def operator_field?(name)
          name.split('.').any? { |part| part.start_with?('$') }
        end

      end

    end
  end
end
