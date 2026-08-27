module Locomotive::Steam

  class ContentType

    include Locomotive::Steam::Models::Entity
    extend Forwardable

    def_delegator :fields, :associations, :association_fields
    def_delegator :fields, :selects, :select_fields
    def_delegator :fields, :files, :file_fields
    def_delegator :fields, :passwords, :password_fields
    def_delegator :fields, :default, :fields_with_default

    def initialize(attributes = {})
      super({
        order_by:           '_position',
        order_direction:    'asc',
        recaptcha_required: false
      }.merge(attributes))
    end

    def fields
      # Note: this returns an instance of the ContentTypeFieldRepository class
      self.entries_custom_fields
    end

    def fields_by_name
      @fields_by_name ||= (fields.all.inject({}) do |memo, field|
        memo[field.name] = field
        memo
      end).with_indifferent_access
    end

    def localized_names
      # FIXME: select type fields are a bit specific. The label of the options is localized
      # even if the select itself is not (see the _cast_select method in the content_entry entity class)
      fields.localized_names + select_fields.map(&:name)
    end

    def localized?
      !fields.localized_names.blank?
    end

    def self.entry_name_owners(fields)
      fields.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |field, owners|
        field.occupied_names.each { |name| owners[name] << field }
      end
    end

    def fields_by_persisted_name
      @fields_by_persisted_name ||= fields_by_name.values
        .select { |field| field.persisted_name && field.persisted_name != field.name.to_s }
        .to_h { |field| [field.persisted_name, field] }
    end

    def unqueryable_field_names
      @unqueryable_field_names ||= fields.all
        .select { |field| field.persisted_name.nil? }
        .flat_map(&:occupied_names)
    end

    # A collision invalidates the shared name and every field that owns it.
    def ambiguous_field_names
      @ambiguous_field_names ||= self.class.entry_name_owners(fields.all).flat_map do |name, owners|
        contested = owners.size > 1 ||
          (ContentTypeField.reserved_name?(name) && owners.any? { |field| field.name.to_s == name })

        contested ? [name, *owners.map { |field| field.name.to_s }] : []
      end.uniq
    end

    def persisted_field_names
      [].tap do |names|
        fields_by_name.each do |name, field|
          _name = field.persisted_name
          names << _name if _name
        end
      end
    end

    def label_field_name
      (self[:label_field_name] || fields.first.name).to_sym
    end

    def field_label_of(name)
      fields_by_name[name].label.downcase
    end

    def order_by
      name = self[:order_by] == 'manually' ? '_position' : self[:order_by]

      # check if name is an id of field
      if field = fields.find(name)
        name = field.name
      end

      { name.to_sym => self.order_direction.to_s }
    end

    def recaptcha_required?
      !!self.recaptcha_required
    end

  end
end
