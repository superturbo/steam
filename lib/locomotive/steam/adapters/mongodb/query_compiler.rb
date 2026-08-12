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

        def initialize(aliases)
          @aliases = aliases
        end

        # MongoDB treats limit 0 as unlimited; use a match-none filter after
        # validating the criteria.
        def compile(criteria, sort:, fields:, skip:, limit:)
          empty_window = limit == 0
          filter       = build_filter(criteria)

          CompiledQuery.new(
            filter: empty_window ? match_none_filter : filter,
            options: {
              sort: build_sort(sort),
              projection: build_fields(fields),
              skip: skip,
              limit: empty_window ? nil : limit
            }.compact
          )
        end

        private

        def build_filter(criteria)
          Adapters::Query::Criteria.reject_raw_operators!(criteria)

          clauses = criteria.map { |key, value| clause_for(key, value) }

          case clauses.length
          when 0 then {}
          when 1 then clauses.first
          else { '$and' => clauses }
          end
        end

        def clause_for(key, value)
          field, operator = Adapters::Query::Operators.decode(key)

          operator ? expand(field, operator, value) : literal(field, value)
        end

        # Sort and projection are a separate boundary from the criteria — a
        # Mongo-only field such as $natural must not reach the driver either.
        def field_name!(subject, name)
          text = Adapters::Query::Text.utf8(name.to_s)

          raise Adapters::Query::InvalidValue, "a #{subject} must be readable text" if text.nil?

          if text.split('.').any? { |part| part.start_with?('$') }
            raise Adapters::Query::UnsupportedOperator,
                  "#{subject} may not contain a Mongo operator: #{name.inspect}"
          end

          text
        end

        # A fresh one each time; compiled filters are mutable.
        def match_none_filter
          { '_id' => { '$in' => [] } }
        end

        def literal(field, value)
          normalized = plain_value(value)

          return match_none_filter if Adapters::Query::Values.unmatchable?(normalized)

          { aliased(field) => normalized }
        end

        def expand(field, operator, value)
          operand = operand(operator.value_kind, value)

          if Adapters::Query::Values.unmatchable?(operand)
            # Nothing equals an unmatchable operand, so ne matches everything.
            return operator.name == :ne ? {} : match_none_filter
          end

          { aliased(field) => { operator.mongo_operator => operand } }
        end

        def operand(value_kind, value)
          Adapters::Query::Values.coerce(value_kind, value)
        end

        # Plain field: a Regexp matches as-is and a Range becomes its bounds
        # (honouring an exclusive end); everything else is a literal.
        def plain_value(value)
          case value
          when Regexp then value
          when Range  then range_bounds(value)
          else Adapters::Query::Values.literal(value)
          end
        end

        def range_bounds(range)
          range = Adapters::Query::Values.range(range)

          return range if Adapters::Query::Values.unmatchable?(range)

          bounds = {}
          bounds['$gte'] = range.begin unless range.begin.nil?
          bounds[range.exclude_end? ? '$lt' : '$lte'] = range.end unless range.end.nil?
          bounds
        end

        def build_sort(spec)
          return nil if spec.nil?

          sort = spec.each_with_object({}) do |(field, direction), result|
            next if field.nil? || field.to_s.empty?
            result[aliased(field_name!('sort field', field))] = direction == :desc ? -1 : 1
          end

          sort.empty? ? nil : sort
        end

        def build_fields(list)
          return nil if list.nil?

          fields = Array(list).flatten.compact
          return nil if fields.empty?

          fields.each_with_object({}) do |field, result|
            result[aliased(field_name!('projection field', field))] = 1
          end
        end

        def aliased(field)
          @aliases[field] || field
        end

      end

    end
  end
end
