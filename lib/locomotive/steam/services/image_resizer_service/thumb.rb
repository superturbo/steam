require 'dragonfly'
require 'dragonfly/image_magick/processors/thumb'

module Locomotive
  module Steam
    class ImageResizerService

      class Thumb < ::Dragonfly::ImageMagick::Processors::Thumb

        DECODE = 'jpeg-1x-v1'.freeze

        FIT    = /\A([1-9]\d*)x([1-9]\d*)>?\z/
        FILL   = /\A([1-9]\d*)x([1-9]\d*)(\^|#\w{0,2})\z/
        WIDTH  = /\A([1-9]\d*)x>?\z/
        HEIGHT = /\Ax([1-9]\d*)>?\z/

        def call(content, geometry, opts = {})
          decode = opts['decode']
          raise ArgumentError, "unknown decode option #{decode.inspect}" unless decode.nil? || decode == DECODE
          return super if decode.nil?

          validate!(opts['format'], &is_word)
          validate!(opts['frame'], &is_number)
          ::Dragonfly::ImageMagick::Commands.convert(content, args_for_geometry(geometry), {
            'format'     => opts['format'],
            'frame'      => opts['frame'],
            'input_args' => decoding_size_args(geometry, content.analyse(:image_properties))
          })
        rescue ::Dragonfly::Shell::CommandFailed => e
          Shell.reraise(e)
        end

        private

        def decoding_size_args(geometry, properties)
          width, height = properties['width'].to_i, properties['height'].to_i
          return unless properties['format'] == 'jpeg' && width > 0 && height > 0

          ratio = output_ratio(geometry, width, height)
          return if ratio.nil?

          scale = (ratio * 8).ceil / 8.0
          return if scale >= 1

          # Rounding up can make the JPEG decoder select a larger scale.
          size = [(width * scale).floor, (height * scale).floor]
          "-define jpeg:size=#{size.join('x')}" if size.all?(&:positive?)
        end

        def output_ratio(geometry, width, height)
          case geometry
          when FIT    then [$1.to_f / width, $2.to_f / height].min
          when FILL   then [$1.to_f / width, $2.to_f / height].max
          when WIDTH  then $1.to_f / width
          when HEIGHT then $1.to_f / height
          end
        end

      end

    end
  end
end
