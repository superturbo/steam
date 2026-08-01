module AdapterParityFixture

  # Compiles the fixture's Wagon files into the documents Engine would persist.
  module MongoDBDocuments

    SITES_COLLECTION           = 'locomotive_sites'
    PAGES_COLLECTION           = 'locomotive_pages'
    SECTIONS_COLLECTION        = 'locomotive_sections'
    SNIPPETS_COLLECTION        = 'locomotive_snippets'
    TRANSLATIONS_COLLECTION    = 'locomotive_translations'
    THEME_ASSETS_COLLECTION    = 'locomotive_theme_assets'
    CONTENT_TYPES_COLLECTION   = 'locomotive_content_types'
    CONTENT_ENTRIES_COLLECTION = 'locomotive_content_entries'

    COLLECTIONS = [SITES_COLLECTION, PAGES_COLLECTION, SECTIONS_COLLECTION, SNIPPETS_COLLECTION,
                   TRANSLATIONS_COLLECTION, THEME_ASSETS_COLLECTION,
                   CONTENT_TYPES_COLLECTION, CONTENT_ENTRIES_COLLECTION].freeze

    module_function

    def documents
      {
        SITES_COLLECTION           => [site],
        PAGES_COLLECTION           => MongoDBPages.documents,
        SECTIONS_COLLECTION        => WagonSections.all.map { |declared| section(declared[:slug]) },
        SNIPPETS_COLLECTION        => WagonSnippets.all.map { |declared| snippet(declared[:slug]) },
        TRANSLATIONS_COLLECTION    => WagonTranslations.all.map { |declared| translation(declared[:key]) },
        THEME_ASSETS_COLLECTION    => WagonThemeAssets.all.map { |declared| theme_asset(declared[:local_path]) },
        CONTENT_TYPES_COLLECTION   => WagonSite.content_types.map { |type| content_type(type.fetch('slug')) },
        CONTENT_ENTRIES_COLLECTION => WagonSite.content_types.flat_map { |type| entries(type.fetch('slug')) }
      }
    end

    # Engine persists the definition the author wrote; only Wagon's loader
    # rewrites it on the way in.
    def section(slug)
      declared = WagonSections.section(slug)

      {
        '_id'        => WagonSite.oid("section:#{slug}"),
        'site_id'    => WagonSite.site_id,
        'name'       => WagonSections.name(slug),
        'slug'       => slug,
        'template'   => declared[:template],
        'definition' => declared[:definition]
      }
    end

    # A locale without a file becomes a locale without a key, so both stores
    # have to reach the default locale on their own.
    def snippet(slug)
      declared = WagonSnippets.snippet(slug)

      {
        '_id'      => WagonSite.oid("snippet:#{slug}"),
        'site_id'  => WagonSite.site_id,
        'name'     => WagonSnippets.name(slug),
        'slug'     => slug,
        'template' => declared[:templates].transform_keys(&:to_s)
      }
    end

    def theme_asset(local_path)
      declared = WagonThemeAssets.asset(local_path)

      {
        '_id'        => WagonSite.oid("theme-asset:#{local_path}"),
        'site_id'    => WagonSite.site_id,
        'local_path' => local_path,
        'folder'     => declared.fetch(:folder),
        # Engine stores an MD5 of the uploaded file.
        'checksum'   => Digest::MD5.hexdigest(File.binread(declared.fetch(:source)))
      }
    end

    def translation(key)
      {
        '_id'     => WagonSite.oid("translation:#{key}"),
        'site_id' => WagonSite.site_id,
        'key'     => key,
        'values'  => WagonTranslations.translation(key).fetch(:values)
      }
    end

    def site
      {
        '_id'           => WagonSite.site_id,
        'name'          => WagonSite.site.fetch('name'),
        'handle'        => WagonSite.site.fetch('subdomain'),
        'timezone_name' => WagonSite.site.fetch('timezone'),
        'locales'       => WagonSite.locales,
        'domains'       => WagonSite.site.fetch('domains')
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
      }.tap { |document| document['description'] = type['description'] if type.key?('description') }
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

      document['hint'] = field['hint'] if field.key?('hint')

      if field['select_options']
        document['select_options'] = WagonSite.select_options(slug, name).each_with_index.map do |option, index|
          { '_id'      => WagonSite.option_id(slug, name, WagonSite.option_name(option)),
            'position' => index,
            'name'     => option }
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

    # Engine stores localized select IDs by locale.
    def select_option_id(slug, name, value)
      return value && WagonSite.option_id(slug, name, value) unless value.is_a?(Hash)

      value.to_h { |locale, option| [locale.to_s, WagonSite.option_id_in(slug, name, locale, option)] }
    end

    def write_attribute(document, slug, name, value)
      field = WagonSite.field(slug, name)

      case field.fetch('type')
      when :select
        document["#{name}_id"] = select_option_id(slug, name, value)
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
