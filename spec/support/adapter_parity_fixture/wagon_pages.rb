module AdapterParityFixture

  # Reads page files independently of the Filesystem loader.
  module WagonPages

    DIRECTORY  = 'app/views/pages'.freeze
    ROOT       = 'index'.freeze
    ATTRIBUTES = %w(position listed published).freeze

    module_function

    def all
      @all ||= begin
        pages = {}

        Dir[File.join(WagonSite::PATH, DIRECTORY, '**', '*.liquid')].sort.each do |file|
          path, locale  = split_locale(relative_path(file))
          page          = pages[path] ||= { path: path, attributes: {}, titles: {}, slugs: {}, bodies: {} }
          front, body   = parse(file)

          page[:titles][locale] = front.fetch('title') { raise Error, "#{path} has no title" }
          page[:slugs][locale]  = front.fetch('slug', File.basename(path))
          page[:bodies][locale] = body

          attribute_names = front.keys - %w(title slug)

          if locale == WagonSite.default_locale
            unknown = attribute_names - ATTRIBUTES

            raise Error, "#{path}.liquid declares #{unknown.inspect}" if unknown.any?

            page[:attributes] = front.slice(*attribute_names)
          elsif attribute_names.any?
            raise Error, "#{path}.#{locale}.liquid may only override title and slug, got #{attribute_names.inspect}"
          end
        end

        pages.values.sort_by { |page| page[:path] }
      end
    end

    def page(path)
      all.detect { |page| page[:path] == path } || raise(Error, "unknown page: #{path.inspect}")
    end

    def parent_path(path)
      return nil if path == ROOT

      directory = File.dirname(path)

      directory == '.' ? ROOT : directory
    end

    def depth(path)
      path == ROOT ? 0 : path.count('/') + 1
    end

    def relative_path(file)
      file.sub("#{File.join(WagonSite::PATH, DIRECTORY)}/", '').sub(/\.liquid\z/, '')
    end

    # A suffix is a locale or a mistake; it never silently becomes a new page.
    def split_locale(path)
      directory, name = File.split(path)
      base, suffix    = name.split('.', 2)

      return [path, WagonSite.default_locale] if suffix.nil?

      unless WagonSite.locales.include?(suffix)
        raise Error, "#{path}.liquid: #{suffix.inspect} is not a declared locale"
      end

      [directory == '.' ? base : File.join(directory, base), suffix.to_sym]
    end

    def parse(file)
      match = File.read(file).match(/\A---\s*\n(.*?)\n---\s*\n(.*)\z/m)

      raise Error, "#{File.basename(file)} has no front matter" if match.nil?

      [YAML.safe_load(match[1], aliases: false) || {}, match[2]]
    end

  end

end
