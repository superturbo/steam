module AdapterParityFixture

  # Reads section files independently of the Filesystem loader.
  module WagonSections

    DIRECTORY = 'app/views/sections'.freeze

    module_function

    def all
      @all ||= Dir[File.join(WagonSite::PATH, DIRECTORY, '*.liquid')].sort.map do |file|
        slug = File.basename(file, '.liquid')

        raise Error, "#{File.basename(file)}: a section slug has no suffix" if slug.include?('.')

        definition, template = WagonTemplate.read(file)

        validate!(slug, definition)

        { slug: slug, definition: definition, template: template }
      end
    end

    def section(slug)
      all.detect { |section| section[:slug] == slug } || raise(Error, "unknown section: #{slug.inspect}")
    end

    # Wagon names a section after its file, so the definition's own name is
    # never what Steam reads back.
    def name(slug)
      section(slug)

      slug.humanize
    end

    # The definition is read as written; only what the assertions rely on is
    # checked here.
    def validate!(slug, definition)
      settings = definition.fetch('settings') { raise Error, "#{slug}.liquid has no settings" }
      ids      = settings.map { |setting| setting.fetch('id') { raise Error, "#{slug}.liquid: a setting has no id" } }

      WagonSite.reject_duplicates!(ids, "setting on #{slug}")

      stated = definition.dig('default', 'settings')&.keys || []
      absent = stated - ids

      raise Error, "#{slug}.liquid defaults #{absent.inspect}" if absent.any?
    end

  end

end
