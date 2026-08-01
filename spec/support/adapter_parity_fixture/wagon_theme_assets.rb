module AdapterParityFixture

  # Reads public files independently of the Filesystem loader.
  module WagonThemeAssets

    DIRECTORY = 'public'.freeze
    SAMPLES   = 'samples'.freeze

    module_function

    def all
      @all ||= begin
        root = File.join(WagonSite::PATH, DIRECTORY)

        Dir[File.join(root, '**', '*')].sort.filter_map do |file|
          local_path = file.sub("#{root}/", '')

          next if File.directory?(file) || excluded?(local_path)

          { source: file, local_path: local_path, folder: File.dirname(local_path) }
        end
      end
    end

    def asset(local_path)
      all.detect { |asset| asset[:local_path] == local_path } ||
        raise(Error, "unknown theme asset: #{local_path.inspect}")
    end

    # Samples and partials are not theme assets.
    def excluded?(local_path)
      local_path.start_with?("#{SAMPLES}/") || File.basename(local_path).start_with?('_')
    end

  end

end
