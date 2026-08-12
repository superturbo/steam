module Locomotive::Steam
  module Models

    module Repository

      extend ActiveSupport::Concern
      extend Forwardable

      class RecordNotFound < StandardError; end

      attr_accessor :adapter, :scope, :local_conditions

      def_delegators :@scope, :site, :site=, :locale, :locale=
      def_delegators :all, :each

      def initialize(adapter, site = nil, locale = nil)
        @adapter  = adapter
        @scope    = Scope.new(site, locale)
        @local_conditions = {}
      end

      def initialize_copy(source)
        super
        @scope            = source.scope.dup
        @local_conditions = source.local_conditions.dup
        @mapper           = nil
      end

      def build(attributes, &block)
        mapper.build_entity(attributes)
      end

      def create(entity)
        adapter.create(mapper, scope, entity)
      end

      def update(entity)
        adapter.update(mapper, scope, entity)
      end

      def inc(entity, attribute, amount = 1)
        adapter.inc(mapper, scope, entity, attribute, amount)
      end

      def delete(entity)
        adapter.delete(mapper, scope, entity)
      end

      def find(id)
        adapter.find(mapper, scope, id)
      end

      def query(&block)
        adapter.query(mapper, scope, &block)
      end

      def count(&block)
        adapter.count(mapper, scope, &block)
      end

      def first(&block)
        adapter.query(mapper, scope, &block).first
      end

      def last(&block)
        adapter.query(mapper, scope, &block).last
      end

      def k(name, operator)
        adapter.key(name, operator)
      end

      # Keep #all materialized across adapters.
      def all(&block)
        query(&block).all
      end

      def mapper(memoized = true)
        name, options, block = mapper_options

        return @mapper if @mapper && memoized

        @mapper = Mapper.new(name, options, self, &block)
      end

      def i18n_value_of(entity, name)
        mapper.i18n_value_of(entity, name, locale)
      end

      def base_url(entity = nil)
        adapter.base_url(mapper, scope, entity)
      end

      # TODO: not sure about that. could it be used further in the dev
      # def collection_name
      #   mapper.name
      # end

      module ClassMethods

        def mapping(name, options = {}, &block)
          class_eval do
            define_method(:mapper_options) { [name, options, block] }
          end
        end

      end

    end

  end
end
