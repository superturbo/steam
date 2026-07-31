require 'yaml'
require 'digest'

module AdapterParityFixture

  Error = Class.new(StandardError)

  # Read raw Wagon YAML so Mongo does not inherit Filesystem normalization.
  module WagonSite

    PATH = File.expand_path('../../fixtures/adapter_parity', __dir__)

    ASSOCIATIONS = %i(belongs_to has_many many_to_many).freeze

    module_function

    def read_yaml(*path)
      YAML.safe_load_file(File.join(PATH, *path), aliases: false) ||
        raise(Error, "empty fixture file: #{File.join(*path)}")
    end

    def site
      @site ||= read_yaml('config', 'site.yml')
    end

    def locales
      site.fetch('locales')
    end

    def default_locale
      locales.first.to_sym
    end

    def content_types
      @content_types ||= Dir[File.join(PATH, 'app', 'content_types', '*.yml')].sort.map do |file|
        expected = File.basename(file, '.yml')
        type     = read_yaml('app', 'content_types', File.basename(file))

        unless type.fetch('slug') == expected
          raise Error, "#{expected}.yml declares slug #{type['slug'].inspect}"
        end

        type
      end
    end

    def content_type(slug)
      content_types.detect { |type| type['slug'] == slug } ||
        raise(Error, "unknown content type: #{slug.inspect}")
    end

    def label_field_name(slug)
      content_type(slug).fetch('label_field_name')
    end

    def fields(slug)
      @fields ||= {}
      @fields[slug] ||= begin
        declared = content_type(slug).fetch('fields').map do |declaration|
          name, attributes = single_pair(declaration, "#{slug} field")
          attributes ||= {}

          attributes.merge('name' => name, 'type' => attributes.fetch('type', 'string').to_sym)
        end

        reject_duplicates!(declared.map { |field| field['name'] }, "#{slug} field name")
        declared
      end
    end

    def field(slug, name)
      fields(slug).detect { |field| field['name'] == name } ||
        raise(Error, "unknown field #{name.inspect} on #{slug}")
    end

    def association?(type)
      ASSOCIATIONS.include?(type)
    end

    def entries(slug)
      @entries ||= {}
      @entries[slug] ||= begin
        loaded = read_yaml('data', "#{slug}.yml").map do |declaration|
          label, attributes = single_pair(declaration, "#{slug} entry")
          attributes ||= {}
          entry_slug = attributes['_slug']

          unless entry_slug.is_a?(String) && !entry_slug.empty?
            raise Error, "#{slug}/#{label} must have a string _slug"
          end

          { label: label, slug: entry_slug, attributes: attributes.reject { |key, _| key == '_slug' } }
        end

        reject_duplicates!(loaded.map { |entry| entry[:slug] }, "#{slug} entry _slug")
        loaded
      end
    end

    def entry(slug, entry_slug)
      entries(slug).detect { |entry| entry[:slug] == entry_slug } ||
        raise(Error, "unknown entry #{entry_slug.inspect} in #{slug}")
    end

    def single_pair(declaration, what)
      unless declaration.is_a?(Hash) && declaration.size == 1
        raise Error, "#{what} must be a single-key mapping, got #{declaration.inspect}"
      end

      declaration.first
    end

    def reject_duplicates!(values, what)
      duplicate = values.tally.find { |_, count| count > 1 }

      raise Error, "duplicate #{what}: #{duplicate.first.inspect}" if duplicate
    end

    # Semantic keys keep IDs stable when fixture order changes.
    def oid(key)
      BSON::ObjectId.from_string(Digest::SHA256.hexdigest("adapter-parity:#{key}")[0, 24])
    end

    def site_id
      oid('site:adapter-parity')
    end

    def type_id(slug)
      content_type(slug)

      oid("content-type:#{slug}")
    end

    def field_id(slug, name)
      field(slug, name)

      oid("field:#{slug}:#{name}")
    end

    def option_id(slug, name, option)
      unless field(slug, name).fetch('select_options').include?(option)
        raise Error, "unknown option #{option.inspect} on #{slug}/#{name}"
      end

      oid("option:#{slug}:#{name}:#{option}")
    end

    def entry_id(slug, entry_slug)
      entry(slug, entry_slug)

      oid("entry:#{slug}:#{entry_slug}")
    end

  end

end
