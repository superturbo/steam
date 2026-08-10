module Locomotive::Steam
  module Models

    class Mapper

      ASSOCIATION_CLASSES = {
        embedded:     EmbeddedAssociation,
        belongs_to:   BelongsToAssociation,
        has_many:     HasManyAssociation,
        many_to_many: ManyToManyAssociation
      }.freeze

      attr_reader :name, :options, :default_attributes, :localized_attributes, :associations

      def initialize(name, options, repository, &block)
        @name, @options, @repository = name, options, repository

        @localized_attributes = []
        @virtual_attributes   = []
        @default_attributes   = []
        @associations         = []

        @entity_map           = {}
        @after_load           = nil

        instance_eval(&block) if block_given?
      end

      # Virtual attributes are omitted from the stored representation.
      def virtual_attributes(*args)
        @virtual_attributes += [*args]
      end

      def localized_attributes(*args)
        @localized_attributes += [*args]

        @localized_attributes_hash = @localized_attributes.inject({}) do |hash, attribute|
          hash[attribute.to_sym] = true; hash
        end

        @localized_attributes
      end

      def default_attribute(name, value)
        @default_attributes += [[name.to_sym, value]]
      end

      ASSOCIATION_CLASSES.each do |type, _|
        define_method("#{type}_association") do |name, repository_klass, options = nil, &block|
          association(type, name, repository_klass, options, &block)
        end
      end

      def association(type, name, repository_klass, options = nil, &block)
        @associations << [type, name.to_sym, repository_klass, options || {}, block]
      end

      # Runs on an entity read out of a store, never on one the caller builds:
      # only the store knows what a value's representation means.
      def after_load(&block)
        @after_load = block
      end

      def to_entity(attributes)
        cache_entity(entity_klass, attributes) do
          new_entity(attributes).tap { |entity| @after_load&.call(entity, @repository) }
        end
      end

      # The identity map belongs to the store: a caller-built entity never
      # enters it, and never comes back out of it either.
      def build_entity(attributes)
        new_entity(attributes).tap { |entity| localize_input(entity) }
      end

      def deserialize(attributes)
        enhanced_attributes = attributes.with_indifferent_access
        build_localized_attributes(enhanced_attributes)
        build_associations(enhanced_attributes)
        enhanced_attributes
      end

      def serialize(entity)
        entity.serialize.tap do |attributes|
          # scope
          @repository.scope.apply(attributes)

          # localized fields
          @localized_attributes.each do |name|
            next unless entity.attributes.key?(name)

            # hack: force the name for select type fields (content entries only)
            value = entity.send(name)
            value.serialize(attributes, name) if value.respond_to?(:serialize)
          end

          @virtual_attributes.each { |name| attributes.delete(name.to_s) }

          # association name -> id (belongs_to) or ids (many_to_many)
          (entity.associations || {}).each do |name, association|
            association.__serialize__(attributes)
          end
        end
      end

      def entity_klass
        options[:entity]
      end

      def i18n_value_of(entity, name, locale)
        value = entity.send(name.to_sym)
        (value.respond_to?(:translations) ? value[locale] : value)
      end

      def reset_entity_map
        @entity_map = {}
      end

      private

      # create a proxy class for each localized attribute
      def build_localized_attributes(attributes)
        @localized_attributes.each do |name|
          _name = name.to_sym

          # A field the store never held must not materialize on load.
          next unless attributes.key?(_name)

          attributes[_name] = I18nField.new(_name, attributes[_name])
        end
      end

      # create a proxy class for each association
      def build_associations(attributes)
        @associations.each do |(type, name, repository_klass, options, block)|
          klass = ASSOCIATION_CLASSES[type]

          _options = options.merge(association_name: name, mapper_name: self.name)

          attributes[name] = (if type == :embedded
            klass.new(repository_klass, attributes[name], @repository.scope, _options)
          else
            klass.new(repository_klass, @repository.scope, @repository.adapter, _options, &block)
          end)
        end
      end

      def attach_entity_to_associations(entity)
        @associations.each do |(type, name, _)|
          association = entity[name]
          association.__attach__(entity)

          entity.associations[name] = association
        end
      end

      def set_default_attributes(entity)
        @default_attributes.each do |(name, value)|
          _value = value.respond_to?(:call) ? value.call(@repository) : value
          entity.send(:"#{name}=", _value)
        end
      end

      def new_entity(attributes)
        entity_klass.new(deserialize(attributes)).tap do |entity|
          set_default_attributes(entity)

          entity.localized_attributes = @localized_attributes_hash || {}
          entity.associations = {}

          attach_entity_to_associations(entity)

          entity.base_url = @repository.base_url(entity)
        end
      end

      # Stored scalars keep their all-locale fallback; caller input belongs to one locale.
      def localize_input(entity)
        @localized_attributes.each do |name|
          field = entity[name.to_sym]
          next if field.nil?

          default = field.default
          next if default.nil?

          entity[name.to_sym] = I18nField.new(name.to_sym, input_locale => default)
        end
      end

      def input_locale
        @repository.scope.locale || @repository.scope.default_locale ||
          raise(MissingLocale, 'a locale is required to write a localized value')
      end

      def cache_entity(entity_klass, attributes, &block)
        entity_id = attributes['_id'] || attributes[:_id] # FIXME: in Wagon, we deal with symbols

        return yield if entity_id.blank?

        key = "#{entity_klass.to_s}-#{entity_id}"

        if (entity = @entity_map[key]).nil?
          entity = @entity_map[key] = yield
        end

        entity
      end

    end

  end
end
