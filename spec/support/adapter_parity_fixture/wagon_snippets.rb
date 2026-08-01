module AdapterParityFixture

  # Reads snippet files independently of the Filesystem loader. A snippet is a
  # whole file per locale, with no front matter.
  module WagonSnippets

    DIRECTORY = 'app/views/snippets'.freeze

    module_function

    def all
      @all ||= begin
        snippets = {}

        Dir[File.join(WagonSite::PATH, DIRECTORY, '*.liquid')].sort.each do |file|
          slug, locale = split_locale(File.basename(file, '.liquid'))

          (snippets[slug] ||= { slug: slug, templates: {} })[:templates][locale] = File.read(file)
        end

        snippets.each_value do |snippet|
          unless snippet[:templates].key?(WagonSite.default_locale)
            raise Error, "#{snippet[:slug]} has no #{WagonSite.default_locale} file to fall back to"
          end
        end

        snippets.values
      end
    end

    def snippet(slug)
      all.detect { |snippet| snippet[:slug] == slug } || raise(Error, "unknown snippet: #{slug.inspect}")
    end

    # Wagon names a snippet after its file, so the stored name has to match it.
    def name(slug)
      snippet(slug)

      slug.humanize
    end

    # Wagon slugifies the filename, so a file may be named more loosely than
    # the slug it is served under.
    def split_locale(basename)
      name, suffix = basename.split('.', 2)

      return [name.permalink, WagonSite.default_locale] if suffix.nil?

      unless WagonSite.locales.include?(suffix)
        raise Error, "#{basename}.liquid: #{suffix.inspect} is not a declared locale"
      end

      [name.permalink, suffix.to_sym]
    end

  end

end
