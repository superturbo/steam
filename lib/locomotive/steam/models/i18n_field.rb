module Locomotive::Steam
  module Models

    class I18nField

      extend Forwardable

      def_delegators :@translations, :values, :default

      attr_reader :name, :translations

      def initialize(name, translations)
        @name = name
        self.translations = translations
      end

      def initialize_copy(field)
        super
        self.translations = Copy.of(field.translations)
        @scalar_fallback = field.scalar_fallback?
      end

      def [](locale)
        @translations[locale]
      end

      def []=(locale, value)
        @scalar_fallback = false
        @translations[locale] = value
      end

      # Scalar and nil values are all-locale fallbacks. Remember their stored
      # form because nil and {} both produce empty translations.
      def translations=(translations)
        @scalar_fallback = !translations.respond_to?(:fetch)

        translations = Hash.new(translations) if @scalar_fallback
        @translations = translations.with_indifferent_access
      end

      def each(&block)
        @translations.each(&block)
      end

      def blank?
        @translations.default.blank? && (
          @translations.blank? ||
          @translations.values.all? { |v| v.blank? }
        )
      end

      def apply(&block)
        if default
          @translations = Hash.new(yield(default))
        else
          each do |l, _value|
            self[l] = block.arity == 2 ? yield(_value, l) : yield(_value)
          end
        end
        self
      end

      def duplicate(new_name)
        self.class.new(new_name, @scalar_fallback ? default : translations)
      end

      alias :__translations__ :translations

      alias :to_hash :translations

      def serialize(attributes, custom_name = nil)
        attributes[custom_name || @name] = serialized_value
      end

      def to_json
        to_hash.to_json
      end

      protected

      def scalar_fallback?
        @scalar_fallback
      end

      private

      def serialized_value
        return default if @scalar_fallback && @translations.empty?

        @translations
      end

    end

  end
end
