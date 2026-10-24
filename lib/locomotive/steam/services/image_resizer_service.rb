require_relative 'image_resizer_service/local_sources'
require_relative 'image_resizer_service/remote_sources'
require_relative 'image_resizer_service/thumb'
require_relative 'image_resizer_service/shell'
require_relative 'image_resizer_service/convert_arguments'
require_relative 'image_resizer_service/geometry'
require_relative 'image_resizer_service/source_image'

module Locomotive
  module Steam

    class ImageResizerService

      attr_accessor_initialize :resizer

      def resize(source, geometry, convert_args = "")
        return get_url_or_path(source) if disabled? || geometry.blank?

        unless Geometry.allowed?(geometry)
          Locomotive::Common::Logger.error 'Unable to resize on the fly: Steam does not run this geometry'
          return nil
        end

        unless ConvertArguments.allowed?(convert_args)
          Locomotive::Common::Logger.error 'Unable to resize on the fly: Steam does not run these ImageMagick arguments'
          return nil
        end

        if file = fetch_file(source)
          job = oriented_thumb(file, geometry, convert_args)
          job.url
        else
          Locomotive::Common::Logger.error "Unable to resize on the fly: #{source.inspect}"
          nil
        end
      rescue ::Dragonfly::Job::Fetch::NotFound => e
        Locomotive::Common::Logger.error "Unable to resize on the fly: #{e.message}"
        nil
      end

      def disabled?
        resizer.nil? || resizer.plugins[:imagemagick].nil?
      end

      protected

      def fetch_file(source)
        return nil if source.blank?
        url_or_path = get_url_or_path(source)

        if url_or_path =~ Steam::IsHTTP
          remote_source(url_or_path)
        elsif url_or_path
          local_source(url_or_path.sub(/(\?.*)$/, ''))
        end
      end

      def local_source(path)
        resizer.fetch_file(LocalSources.new.path_for(path))
      end

      def remote_source(url)
        RemoteSources.new.check(url)
        resizer.fetch_url(url)
      end

      def get_url_or_path(source)
        value = if source.is_a?(Hash)
          source['url']
        elsif source.respond_to?(:url)
          source.url
        else
          source&.to_s
        end
        value.strip if value
      end

      # ImageMagick orients the image in the resize, before its geometry, rather than after it.
      def oriented_thumb(file, geometry, convert_args)
        words  = Shellwords.split(convert_args)
        orient = words.include?('-auto-orient')
        opts   = orient ? { 'decode' => Thumb::DECODE, 'orient' => true } : { 'decode' => Thumb::DECODE }
        args   = orient ? Shellwords.join(words - ['-auto-orient']) : convert_args

        image_magick_convert(file.thumb(geometry, opts), args)
      end

      def image_magick_convert(job, options = '')
        return job if options.blank?
        job.process(:convert, options)
      end

    end

  end
end
