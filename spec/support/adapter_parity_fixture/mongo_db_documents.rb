module AdapterParityFixture

  # Compiles the fixture's Wagon files into the documents Engine would persist.
  module MongoDBDocuments

    CONTENT_TYPES_COLLECTION   = 'locomotive_content_types'
    CONTENT_ENTRIES_COLLECTION = 'locomotive_content_entries'

    COLLECTIONS = [CONTENT_TYPES_COLLECTION, CONTENT_ENTRIES_COLLECTION].freeze

    module_function

    def documents
      {
        CONTENT_TYPES_COLLECTION   => WagonSite.content_types.map { |type| content_type(type.fetch('slug')) },
        CONTENT_ENTRIES_COLLECTION => WagonSite.content_types.flat_map { |type| entries(type.fetch('slug')) }
      }
    end

    def content_type(slug)
      type  = WagonSite.content_type(slug)
      label = WagonSite.label_field_name(slug)

      {
        '_id'                   => WagonSite.type_id(slug),
        'site_id'               => WagonSite.site_id,
        'name'                  => type.fetch('name'),
        'slug'                  => slug,
        'label_field_name'      => label,
        'label_field_id'        => WagonSite.field_id(slug, label),
        'order_by'              => type.fetch('order_by'),
        'order_direction'       => type.fetch('order_direction', 'asc'),
        'entries_custom_fields' => WagonSite.fields(slug).each_with_index.map { |f, i| field(slug, f, i) }
      }
    end

    def field(slug, field, position)
      name     = field.fetch('name')
      type     = field.fetch('type')
      document = {
        '_id'       => WagonSite.field_id(slug, name),
        'position'  => position,
        'name'      => name,
        'type'      => type.to_s,
        'label'     => field.fetch('label', name.humanize),
        'required'  => field.fetch('required', false),
        'localized' => field.fetch('localized', false),
        'unique'    => field.fetch('unique', false)
      }

      if (options = field['select_options'])
        document['select_options'] = options.each_with_index.map do |option, index|
          { '_id'      => WagonSite.option_id(slug, name, option),
            'position' => index,
            'name'     => { WagonSite.default_locale.to_s => option } }
        end
      end

      if WagonSite.association?(type)
        document['class_name'] = "Locomotive::ContentEntry#{WagonSite.type_id(field.fetch('class_name'))}"
        document['inverse_of'] = field['inverse_of'] if field['inverse_of']
      end

      document
    end

    def entries(slug)
      WagonSite.entries(slug).each_with_index.map { |entry, position| entry(slug, entry, position) }
    end

    def entry(slug, entry, position)
      label = WagonSite.label_field_name(slug)

      document = {
        '_id'             => WagonSite.entry_id(slug, entry[:slug]),
        'site_id'         => WagonSite.site_id,
        'content_type_id' => WagonSite.type_id(slug),
        '_slug'           => WagonSite.locales.to_h { |locale| [locale, entry[:slug]] },
        '_position'       => position,
        '_visible'        => true,
        # Wagon stores the label as the entry key; Engine stores it as a field.
        label             => entry[:label]
      }

      entry[:attributes].each { |name, value| write_attribute(document, slug, name, value) }

      # Match Wagon's inverse-association order derived from file position.
      WagonSite.fields(slug).each do |field|
        next unless field.fetch('type') == :belongs_to

        document["position_in_#{field.fetch('name')}"] = position
      end

      document
    end

    def write_attribute(document, slug, name, value)
      field = WagonSite.field(slug, name)

      case field.fetch('type')
      when :select
        document["#{name}_id"] = value && WagonSite.option_id(slug, name, value)
      when :belongs_to
        document["#{name}_id"] = value && WagonSite.entry_id(field.fetch('class_name'), value)
      when :many_to_many
        target = field.fetch('class_name')

        document["#{name.singularize}_ids"] = Array(value).map { |entry| WagonSite.entry_id(target, entry) }
      when :date_time
        document[name] = value && Time.parse(value).utc
      when :date
        document[name] = value && Date.parse(value)
      else
        document[name] = value
      end
    end

  end

end
