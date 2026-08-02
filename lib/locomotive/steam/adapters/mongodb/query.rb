require_relative 'query_compiler'

module Locomotive::Steam
  module Adapters
    module MongoDB

      class Query

        attr_reader :criteria, :sort

        def initialize(scope, localized_attributes, &block)
          @criteria, @sort, @fields, @skip, @limit = {}, nil, nil, nil, nil
          @scope, @localized_attributes = scope, localized_attributes

          instance_eval(&block) if block_given?
        end

        def where(criterion = nil)
          self.tap do
            @criteria.merge!(criterion) unless criterion.nil?
          end
        end

        def order_by(*args)
          self.tap do
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

        def against(collection)
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
