require_relative 'query_compiler'
require_relative 'id_order_view'

module Locomotive::Steam
  module Adapters
    module MongoDB

      class Query

        attr_reader :criteria, :sort

        def initialize(scope, localized_attributes, &block)
          @criteria, @sort, @fields, @skip, @limit = [], nil, nil, nil, nil
          @scope, @localized_attributes = scope, localized_attributes

          instance_eval(&block) if block_given?
        end

        # A list, not a hash: two calls naming one field are two conditions to
        # meet, and merging would keep only the last.
        def where(criterion = nil)
          self.tap do
            @criteria.concat(criterion.to_a) unless criterion.nil?
          end
        end

        def order_by(*args)
          self.tap do
            raise Adapters::Query::InvalidValue, 'in_id_order and order_by cannot be combined' if @id_order

            @sort = Adapters::Query::OrderBy.decode(*args)
          end
        end

        def only(*args)
          self.tap do
            @fields = [*args]
          end
        end

        def offset(offset)
          self.tap { @skip = Adapters::Query::Window.normalize(offset, :offset) }
        end

        def limit(limit)
          self.tap { @limit = Adapters::Query::Window.normalize(limit, :limit) }
        end

        def in_id_order(ids)
          self.tap do
            raise Adapters::Query::InvalidValue, 'in_id_order and order_by cannot be combined' if @sort

            @id_order = Adapters::Query::IdOrder.normalize(ids)
          end
        end

        def against(collection)
          return id_order_view(collection) if @id_order

          compiled = QueryCompiler.new(build_aliases(@localized_attributes, @scope.locale)).compile(
            @criteria, sort: @sort, fields: @fields, skip: @skip, limit: @limit
          )

          collection.find(apply_tenant_scope(compiled.filter), compiled.options)
        end

        def key(name, operator)
          Adapters::Query::Operators.key(name, operator)
        end

        alias :k :key

        private

        def id_order_view(collection)
          compiled = QueryCompiler.new(build_aliases(@localized_attributes, @scope.locale)).compile(
            @criteria + [[key(:_id, :in), @id_order]], sort: nil, fields: @fields, skip: nil, limit: nil
          )

          IdOrderView.new(collection, apply_tenant_scope(compiled.filter), compiled.options,
                            ids: @id_order, skip: @skip, limit: @limit)
        end

        def build_aliases(localized_attributes, locale)
          localized_attributes.inject({}) do |aliases, name|
            aliases.tap do
              aliases[name.to_s] = "#{name}.#{locale}"
            end
          end
        end

        # Keep reads within the current site.
        def apply_tenant_scope(filter)
          return filter unless @scope.site

          tenant = { 'site_id' => @scope.site._id }
          filter.empty? ? tenant : { '$and' => [filter, tenant] }
        end

      end

    end
  end
end
