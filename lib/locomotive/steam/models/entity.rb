module Locomotive::Steam
  module Models
    module Entity

      include Locomotive::Steam::Models::Concerns::Validation
      include Locomotive::Steam::Models::Concerns::ToJson

      attr_accessor :attributes, :associations, :localized_attributes, :base_url

      def initialize(attributes)
        @attributes = attributes.with_indifferent_access
      end

      # Association proxies must answer for the copied entity.
      def initialize_copy(source)
        super
        @errors     = nil
        @attributes = source.attributes.transform_values do |value|
          value.is_a?(I18nField) ? value.dup : Copy.of(value)
        end

        @associations = (source.associations || {}).each_with_object({}) do |(name, association), copies|
          copies[name] = association.dup.tap do |copy|
            copy.__attach__(self)

            @attributes[name] = copy if @attributes[name].equal?(association)
          end
        end
      end

      def method_missing(name, *args, &block)
        _name = name.to_s
        if attributes.include?(_name)
          self[_name]
        elsif _name.end_with?('=') && attributes.include?(_name.chop)
          self[_name.chop] = args.first
        else
          super
        end
      end

      def respond_to?(name, include_private = false)
        attributes.include?(name.to_s) || super
      end

      def _id
        self['_id']
      end

      def []=(name, value)
        attributes[name] = value
      end

      def [](name)
        attributes[name]
      end

      def change(new_attributes)
        attributes.merge!((new_attributes || {}).with_indifferent_access)
        self
      end

      def serialize
        attributes.dup
      end
    end
  end
end
