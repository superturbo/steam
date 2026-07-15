require 'set'

module Locomotive::Steam
  module Adapters
    module MongoDB

      # Compiles Steam's neutral query DSL into a MongoDB filter structure:
      # operator expansion, localisation aliases, and the list/Range/Set/cast
      # normalisations Mongo requires. Value types (Date, Time, BigDecimal, ...)
      # are left untouched for BSON to serialize. The tenant boundary is not its
      # concern — Query adds it.
      class QueryCompiler

        class UnsupportedOperator < StandardError; end
        class InvalidQueryValue   < StandardError; end

        CompiledQuery = Data.define(:filter, :options)

        # The minimal, supported Steam DSL. DSL operator => [ mongo operator,
        # value kind ]. Plain equality, a regex, and a Range value need no
        # operator suffix.
        OPERATORS = {
          'all'    => ['$all',    :list],
          'in'     => ['$in',     :list],
          'nin'    => ['$nin',    :list],
          'ne'     => ['$ne',     :plain],
          'gt'     => ['$gt',     :plain],
          'gte'    => ['$gte',    :plain],
          'lt'     => ['$lt',     :plain],
          'lte'    => ['$lte',    :plain],
          'exists' => ['$exists', :boolean],
          'size'   => ['$size',   :size]
        }.freeze

        # Known unsupported operator suffixes: raise a clear error rather than
        # silently build a stray dotted field.
        UNSUPPORTED = %w(
          neq not mod elem_match with_size with_type
          near near_sphere within within_box within_circle
          within_spherical_circle within_polygon
          intersects_line intersects_point intersects_polygon
        ).freeze

        TRUE_VALUES = %w(true t yes y 1 1.0).freeze

        def initialize(aliases)
          @aliases = aliases
        end

        def compile(criteria, sort:, fields:, skip:, limit:)
          CompiledQuery.new(
            filter: build_filter(criteria),
            options: {
              sort: build_sort(sort),
              projection: build_fields(fields),
              skip: skip,
              limit: limit
            }.compact
          )
        end

        private

        def build_filter(criteria)
          clauses = criteria.map { |key, value| clause_for(key, value) }

          case clauses.length
          when 0 then {}
          when 1 then clauses.first
          else { '$and' => clauses }
          end
        end

        def clause_for(key, value)
          reject_raw_operators!(key, value)

          field, separator, operator = key.to_s.rpartition('.')

          if separator.empty?
            literal(key.to_s, value)
          elsif OPERATORS.key?(operator)
            expand(field, operator, value)
          elsif UNSUPPORTED.include?(operator)
            raise UnsupportedOperator, "#{operator} is not supported"
          else
            literal(key.to_s, value)
          end
        end

        # Reject raw Mongo operators from user criteria.
        def reject_raw_operators!(key, value)
          raise UnsupportedOperator, "keys may not contain a Mongo operator: #{key.inspect}" if operator_name?(key)
          reject_operator_values!(value)
        end

        def reject_operator_values!(value)
          case value
          when Hash
            value.each do |k, v|
              raise UnsupportedOperator, "values may not contain a Mongo operator: #{k.inspect}" if operator_name?(k)
              reject_operator_values!(v)
            end
          when Array, Set
            value.each { |item| reject_operator_values!(item) }
          end
        end

        def operator_name?(name)
          name.to_s.split('.').any? { |part| part.start_with?('$') }
        end

        def literal(field, value)
          { aliased(field) => plain_value(value) }
        end

        def expand(field, operator, value)
          mongo_operator, kind = OPERATORS[operator]
          { aliased(field) => { mongo_operator => operand(kind, value) } }
        end

        def operand(kind, value)
          case kind
          when :list    then list_value(value)
          when :boolean then boolean_value(value)
          when :size    then size_value(value)
          else value
          end
        end

        def plain_value(value)
          case value
          when Range then { '$gte' => value.min, '$lte' => value.max }
          when Set   then value.to_a
          else value
          end
        end

        # Mongo list operators require an array.
        def list_value(value)
          case value
          when Array      then value
          when Range, Set then value.to_a
          else [value]
          end
        end

        def boolean_value(value)
          TRUE_VALUES.include?(value.to_s.downcase)
        end

        def size_value(value)
          int = case value
                when Integer then value
                when String  then (Integer(value) if value.match?(/\A\d+\z/))
                end

          unless int.is_a?(Integer) && int >= 0
            raise InvalidQueryValue, "$size expects a non-negative integer, got #{value.inspect}"
          end

          int
        end

        def build_sort(spec)
          return nil if spec.nil?

          sort = sort_pairs(spec).each_with_object({}) do |(field, direction), result|
            next if field.nil? || field.to_s.empty?
            raise UnsupportedOperator, "sort field may not contain a Mongo operator: #{field.inspect}" if operator_name?(field)
            result[aliased(field.to_s)] = direction_value(direction)
          end

          sort.empty? ? nil : sort
        end

        # Flattens the shapes Query#decode_order_by produces — a Hash, or
        # (possibly nested) [field, direction] / [field] tuples — into pairs.
        def sort_pairs(spec)
          case spec
          when Hash
            spec.to_a
          when Array
            return [] if spec.empty?
            if spec.first.is_a?(Array) || spec.first.is_a?(Hash)
              spec.flat_map { |element| sort_pairs(element) }
            else
              [[spec[0], spec[1]]]
            end
          else
            []
          end
        end

        def direction_value(direction)
          case direction
          when 1  then 1
          when -1 then -1
          when Numeric
            raise InvalidQueryValue, "sort direction must be 1 or -1, got #{direction.inspect}"
          else
            direction.to_s.match?(/\Adesc/i) ? -1 : 1
          end
        end

        def build_fields(list)
          return nil if list.nil?

          fields = Array(list).flatten.compact
          return nil if fields.empty?

          fields.each_with_object({}) do |field, result|
            raise UnsupportedOperator, "projection field may not contain a Mongo operator: #{field.inspect}" if operator_name?(field)
            result[aliased(field.to_s)] = 1
          end
        end

        def aliased(field)
          @aliases[field] || field
        end

      end

    end
  end
end
