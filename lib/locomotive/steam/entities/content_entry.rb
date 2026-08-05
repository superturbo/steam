require 'bcrypt'

module Locomotive::Steam

  class ContentEntry

    include Locomotive::Steam::Models::Entity

    attr_accessor :content_type, :site

    NIL_IS_THE_ONLY_BLANK    = %i(boolean integer float date date_time).freeze
    REQUIRED_FROM_ATTRIBUTES = %i(belongs_to many_to_many file).freeze

    private_constant :NIL_IS_THE_ONLY_BLANK, :REQUIRED_FROM_ATTRIBUTES

    def initialize(attributes = {})
      super({
        _visible:     true,
        _position:    0,
        created_at:   Time.zone.now,
        updated_at:   Time.zone.now
      }.merge(attributes))
    end

    # Positional locale preserves calls such as change(title: 'x').
    def change(new_attributes, locale = nil)
      super((new_attributes || {}).each_with_object({}) do |(name, value), changed|
        changed[name] = localized?(name) ? localized_change(name, value, locale) : value
      end)
    end

    def _id; self[:_id] || self[:id]; end

    def _visible?; !!self[:_visible]; end
    alias :visible? :_visible?

    def _slug; self[:_slug]; end
    alias :_permalink :_slug

    def method_missing(name, *args, &block)
      if is_dynamic_attribute?(name)
        cast_value(name)
      elsif attributes.include?(name)
        self[name]
      else
        super
      end
    end

    def valid?
      errors.clear

      validate_required_fields(normalize_fields)

      errors.empty?
    end

    def content_type
      @content_type || attributes[:content_type]
    end

    def content_type_id
      @content_type.try(&:_id) || attributes[:content_type_id]
    end

    def content_type_slug
      content_type.slug
    end

    def _class_name
      "Locomotive::ContentEntry#{content_type_id}"
    end

    def _label
      self[content_type.label_field_name]
    end

    def _label_of(name)
      content_type.field_label_of(name)
    end

    def localized_attributes
      @localized_attributes.tap do |hash|
        if hash && hash.has_key?(content_type.label_field_name.to_sym)
          hash[:_label] = true
        end
      end
    end

    def serialize
      super.merge(content_type_id: content_type_id)
    end

    def to_hash
      hash = {}

      # default attributes
      _attributes = %i(_id _slug _visible _position content_type_slug created_at updated_at)

      # stack level too deep raised if the _label field is an association (belongs_to, ...etc)
      unless content_type.fields_by_name[content_type.label_field_name].is_relationship?
        _attributes << :_label
      end

      # dynamic attributes
      _attributes += content_type.persisted_field_names

      # Missing fields are nil in output but remain absent from the entry.
      _attributes.each do |name|
        hash[name.to_s] = respond_to?(name) ? send(name) : nil
      end

      # errors?
      hash['errors'] = self.errors.to_hash.stringify_keys unless self.errors.empty?

      hash
    end

    def to_liquid
      Locomotive::Steam::Liquid::Drops::ContentEntry.new(self)
    end

    private

    # Invalid input remains in the attributes.
    def normalize_fields
      content_type.fields_by_name.each_value.with_object([]) do |field, invalid|
        name = field.persisted_name
        next unless name && attributes.key?(name)

        begin
          attributes[name] = normalized_value(field, attributes[name])
        rescue ContentFieldValues::ParseError
          errors.add(field.name.to_sym, :invalid)
          invalid << field.name.to_sym
        end
      end
    end

    def normalized_value(field, value)
      return ContentFieldValues.normalize_input(field.type, value, site) unless value.respond_to?(:translations)

      value.dup.apply { |translated| ContentFieldValues.normalize_input(field.type, translated, site) }
    end

    def validate_required_fields(invalid)
      content_type.fields.required.each do |field|
        name = field.name.to_sym
        # Nothing points at an entry being created, so a has_many cannot answer.
        next if field.type == :has_many || invalid.include?(name)

        errors.add(name, :blank) if missing?(field)
      end
    end

    def missing?(field)
      value = required_value_for(field)
      value = value[site.default_locale] if value.respond_to?(:translations)

      NIL_IS_THE_ONLY_BLANK.include?(field.type) ? value.nil? : value.blank?
    end

    # An association proxy and a file read back as objects whether or not they
    # hold anything.
    def required_value_for(field)
      return attributes[field.persisted_name] if REQUIRED_FROM_ATTRIBUTES.include?(field.type)

      send(field.name)
    end

    def localized?(name)
      (localized_attributes || {})[name.to_sym]
    end

    def localized_change(name, value, locale)
      return value if value.respond_to?(:translations)

      current = self[name]
      field   = current.respond_to?(:translations) ? current.dup : Models::I18nField.new(name.to_sym, {})

      value.is_a?(Hash) ? field.translations = value : field[locale || site.default_locale] = value

      field
    end

    def is_dynamic_attribute?(name)
      content_type.fields_by_name.has_key?(name)
    end

    def cast_value(name)
      field = content_type.fields_by_name[name]

      begin
        _cast_value(field)
      rescue ContentFieldValues::ConfigurationError
        raise
      rescue Exception => e
        Locomotive::Common::Logger.info "[#{content_type.slug}][#{_label}] Unable to cast the \"#{name}\" field, reason: #{e.message}".yellow
        nil
      end
    end

    def _cast_value(field)
      if private_methods.include?(:"_cast_#{field.type}")
        send(:"_cast_#{field.type}", field)
      else
        attributes[field.name]
      end
    end

    def _cast_integer(field)
      _cast_number(field, :integer)
    end

    def _cast_float(field)
      _cast_number(field, :float)
    end

    def _cast_number(field, type)
      _cast_convertor(field.name) { |value| ContentFieldValues.normalize_input(type, value, site) }
    end

    def _cast_json(field)
      _cast_convertor(field.name) { |value| ContentFieldValues.normalize_input(:json, value, site) }
    end

    def _cast_password(field)
      _cast_convertor(:"#{field.name}_hash") do |value|
        value.blank? ? nil : BCrypt::Password.new(value)
      end
    end

    def _cast_file(field)
      _cast_convertor(field.name) do |value, locale|
        if value.respond_to?(:url)
          value
        else
          size = (self[:"#{field.name}_size"] || {})[locale || 'default']
          FileField.new(value, self.base_url, size, self.updated_at)
        end
      end
    end

    def _cast_date(field)
      _cast_time(field, :to_date)
    end

    def _cast_date_time(field)
      _cast_time(field, :to_datetime)
    end

    def _cast_time(field, end_method)
      _cast_convertor(field.name) do |value|
        next value unless value.is_a?(String)

        next ContentFieldValues.date(value) if end_method == :to_date

        ContentFieldValues.date_time(value, ContentFieldValues.zone_of(site)).getutc
      end
    end

    def _cast_select(field)
      options = field.select_options

      if (_value = @attributes[:"#{field.name}_id"]).respond_to?(:translations)
        # the field is localized, so get the labels in all the locales
        # (2 different locales might point to different options)
        if _value.default
          # unique value for all the locales, so grab the option
          name = options.by_id_or_name(_value.default)&.name
          name&.duplicate(field.name)
        else
          @attributes[field.name] = _value.duplicate(field.name)

          _cast_convertor(field.name, true) do |value, locale|
            name = options.by_id_or_name(value)&.name
            name.try(:[], locale)
          end
        end
      else
        # the field is not localized, we only have the id of the option (or its name if a
        # contact form submission in Wagon for instance),
        # so just copy the labels (in all the locales) of the matching select option
        if name = options.by_id_or_name(_value)&.name # this should either return an i18nField or nil
          attributes[field.name] = name.dup
        end
      end
    end

    def _cast_convertor(name, nil_locale = false, &block)
      if (value = attributes[name]).respond_to?(:translations)
        value.apply(&block)
      else
        nil_locale ? yield(value, nil) : yield(value)
      end
    end

    # Represent a file
    class FileField

      attr_accessor_initialize :filename, :base, :size, :updated_at

      def url
        return if filename.blank?
        base.blank? ? filename : "#{base}/#{filename}"
      end

      def to_hash
        { 'url' => url, 'filename' => filename, 'size' => size, 'updated_at' => updated_at }
      end

      def to_json
        url
      end

      def to_liquid
        Locomotive::Steam::Liquid::Drops::UploadedFile.new(self)
      end

    end

  end

end
