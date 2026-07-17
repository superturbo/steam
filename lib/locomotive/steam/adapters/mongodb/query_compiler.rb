require 'set'

require_relative '../query'

module Locomotive::Steam
  module Adapters
    module MongoDB

      # Compiles Steam's neutral query DSL into a MongoDB filter structure using
      # the shared operator registry and value coercions (Adapters::Query).
      # Value types (Date, Time, BigDecimal, ...) are left untouched for BSON to
      # serialize. The tenant boundary is not its concern — Query adds it.
      class QueryCompiler

        CompiledQuery = Data.define(:filter, :options)

        # Operator suffixes Steam does not support: raised with a clear error
        # rather than silently building a stray dotted field. An unknown, non-
        # operator suffix stays a literal sub-document path for now.
        UNSUPPORTED = %w(
          neq not mod elem_match with_size with_type
          near near_sphere within within_box within_circle
          within_spherical_circle within_polygon
          intersects_line intersects_point intersects_polygon
        ).freeze

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

          field, separator, suffix = key.to_s.rpartition('.')

          if separator.empty?
            literal(key.to_s, value)
          elsif (operator = Adapters::Query::Operators[suffix])
            expand(field, operator, value)
          elsif UNSUPPORTED.include?(suffix)
            raise Adapters::Query::UnsupportedOperator, "#{suffix} is not supported"
          else
            literal(key.to_s, value)
          end
        end

        # Reject raw Mongo operators from user criteria (defense in depth, ahead
        # of the registry lookup).
        def reject_raw_operators!(key, value)
          reject_raw_operator!('keys', key)
          reject_operator_values!(value)
        end

        def reject_operator_values!(value)
          case value
          when Hash
            value.each do |k, v|
              reject_raw_operator!('values', k)
              reject_operator_values!(v)
            end
          when Array, Set
            value.each { |item| reject_operator_values!(item) }
          end
        end

        def reject_raw_operator!(subject, name)
          return unless operator_name?(name)

          raise Adapters::Query::UnsupportedOperator,
                "#{subject} may not contain a Mongo operator: #{name.inspect}"
        end

        def operator_name?(name)
          name.to_s.split('.').any? { |part| part.start_with?('$') }
        end

        def literal(field, value)
          { aliased(field) => plain_value(value) }
        end

        def expand(field, operator, value)
          { aliased(field) => { operator.mongo_operator => operand(operator.value_kind, value) } }
        end

        def operand(value_kind, value)
          case value_kind
          when :list    then Adapters::Query::Values.list(value)
          when :boolean then Adapters::Query::Values.boolean(value)
          when :size    then Adapters::Query::Values.size(value)
          else value
          end
        end

        # Plain field: a scalar or Regexp matches as-is; a Range becomes its
        # bounds (honouring an exclusive end); a Set becomes an array.
        def plain_value(value)
          case value
          when Range then range_bounds(value)
          when Set   then value.to_a
          else value
          end
        end

        def range_bounds(range)
          range = Adapters::Query::Values.range(range)

          bounds = {}
          bounds['$gte'] = range.begin unless range.begin.nil?
          bounds[range.exclude_end? ? '$lt' : '$lte'] = range.end unless range.end.nil?
          bounds
        end

        def build_sort(spec)
          return nil if spec.nil?

          sort = sort_pairs(spec).each_with_object({}) do |(field, direction), result|
            next if field.nil? || field.to_s.empty?
            reject_raw_operator!('sort field', field)
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
            raise Adapters::Query::InvalidValue, "sort direction must be 1 or -1, got #{direction.inspect}"
          else
            direction.to_s.match?(/\Adesc/i) ? -1 : 1
          end
        end

        def build_fields(list)
          return nil if list.nil?

          fields = Array(list).flatten.compact
          return nil if fields.empty?

          fields.each_with_object({}) do |field, result|
            reject_raw_operator!('projection field', field)
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
