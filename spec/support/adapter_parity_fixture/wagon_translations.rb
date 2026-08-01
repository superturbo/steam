module AdapterParityFixture

  # Reads config/translations.yml independently of the Filesystem loader.
  module WagonTranslations

    module_function

    def all
      @all ||= WagonSite.read_yaml('config', 'translations.yml').map do |key, values|
        validate!(key, values)

        { key: key, values: values }
      end
    end

    def translation(key)
      all.detect { |translation| translation[:key] == key } || raise(Error, "unknown translation: #{key.inspect}")
    end

    # A bare string would make values[locale] a substring lookup, and anything
    # but a string reaches Liquid::Template.parse as it is.
    def validate!(key, values)
      unless values.is_a?(Hash) && values.each_value.all?(String)
        raise Error, "#{key} must map locales to strings, got #{values.inspect}"
      end

      undeclared = values.keys - WagonSite.locales

      raise Error, "#{key} translates #{undeclared.inspect}" if undeclared.any?
    end

  end

end
