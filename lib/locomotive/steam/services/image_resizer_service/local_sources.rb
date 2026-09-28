module Locomotive
  module Steam
    class ImageResizerService

      # The files a resize job may read: regular files inside the real asset path.
      # It checks a path before Steam signs it, and matches as a Dragonfly fetch_file whitelist pattern
      # every time a job is served.
      class LocalSources

        def ===(path)
          check(path)
          true
        rescue ::Dragonfly::Job::Fetch::NotFound
          false
        end

        # The path Steam signs for a source written relative to the asset path.
        def path_for(source)
          refuse(source, 'is not found') if source.include?("\0")

          File.join(configuration.asset_path.to_s, source).tap { |path| check(path) }
        end

        def check(path)
          refuse(path, 'is not found') if path.include?("\0")

          root = asset_root
          real = File.realpath(path)

          refuse(path, 'is outside the asset path') unless real.start_with?(root + File::SEPARATOR)
          refuse(path, 'is not a file') unless File.file?(real)

          real
        rescue SystemCallError
          refuse(path, 'is not found')
        end

        private

        def asset_root
          path = configuration.asset_path
          raise ::Dragonfly::Job::Fetch::NotFound, 'no asset path holds resize sources' if path.blank?

          File.realpath(path)
        end

        def refuse(path, reason)
          raise ::Dragonfly::Job::Fetch::NotFound, "the resize source #{path.inspect} #{reason}"
        end

        def configuration
          Locomotive::Steam.configuration
        end

      end

    end
  end
end
