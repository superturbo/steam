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

        # ImageMagick reads a frame index as a floating-point number, exact up to 2**53.
        MAX_FRAME_INDEX = 2**53

        # Their encoded image leaves the canvas out: dropped, or kept by PNG as metadata alone.
        FORMATS_WITHOUT_CANVAS = %w(jpg jpeg png png8 png24 png32 png48 png64 tif tiff bmp avif psd ico).freeze

        # Their encoder keeps each frame's canvas as it is, building none of its own.
        FORMATS_WITH_FRAME_CANVASES = %w(miff).freeze

        # The sizes a JPEG decodes to, k/8 of each side rounded up, that are no smaller than the size asked for.
        def self.decoded_sizes(width, height, (least_width, least_height))
          (1..8).map { |eighths| [(width * eighths + 7) / 8, (height * eighths + 7) / 8] }
                .select { |w, h| w >= least_width && h >= least_height }
        end

        def call(content, geometry, opts = {})
          Geometry.check!(geometry)

          decode = opts['decode']
          raise Shell::RefusedJob, 'Steam does not run this decode option' unless decode.nil? || decode == DECODE

          validate!(opts['format'], &is_word)
          opts = opts.merge('frame' => frame_index(opts['frame'])) unless opts['frame'].nil?

          image = content.analyse(:steam_image)
          size  = decoding_size(geometry, image) if decode
          check_sizes!(geometry, content, image, opts, size)
          return super(content, geometry, opts) if decode.nil?

          ::Dragonfly::ImageMagick::Commands.convert(content, args_for_geometry(geometry), {
            'format'     => opts['format'],
            'frame'      => opts['frame'],
            'input_args' => ("-define jpeg:size=#{size.join('x')}" if size)
          })
        rescue ::Dragonfly::Shell::CommandFailed => e
          Shell.reraise(e)
        end

        private

        # Every frame the job reads, at each size it may decode to.
        def check_sizes!(geometry, content, image, opts, decoding_size)
          frames = image['frames']
          # Keep checking source frames when ImageMagick ignores the index.
          frames = frames.values_at(opts['frame']).compact.presence || frames unless opts['frame'].nil?
          format = output_format(content, image, opts)
          canvas = keeps_canvas?(format, frames)
          # An encoder that keeps a canvas may build its own: one shared across frames, or one sized from an offset.
          builds = canvas && !FORMATS_WITH_FRAME_CANVASES.include?(format)

          inputs = frames.flat_map do |width, height, canvas_width, canvas_height, x, y|
            next self.class.decoded_sizes(width, height, decoding_size).map { |size| [*size, {}] } if decoding_size

            [[width, height, { canvas: ([canvas_width, canvas_height] if canvas), offset: ([x, y] if builds) }]]
          end

          outputs = inputs.map { |w, h, placement| Geometry.output_size(geometry, w, h, **placement) }
          outputs << shared_canvas(geometry, inputs, outputs) if builds && outputs.size > 1

          return if inputs.any? && inputs.all? { |w, h| Geometry.resized_within_bounds?(geometry, w, h) } &&
                    outputs.all? { |output| Geometry.output_within_bounds?(output) }

          raise Shell::RefusedJob, 'Steam does not resize to this size'
        end

        # If any canvas may vanish, bound the shared canvas by every frame's offset.
        def shared_canvas(geometry, inputs, outputs)
          sides = outputs.transpose.map(&:max)
          return sides unless inputs.any? { |w, h, placement| Geometry.canvas_may_vanish?(w, h, placement[:canvas]) }

          reaches = inputs.map { |w, h, placement| Geometry.offset_reach(geometry, w, h, placement[:offset]) }
          sides.zip(*reaches).map(&:max)
        end

        # Accept a single non-negative frame index, not bracket geometry.
        def frame_index(frame)
          index = frame.to_i if frame.is_a?(Integer) || (frame.is_a?(String) && frame.match?(/\A\d+\z/))
          return index if index&.between?(0, MAX_FRAME_INDEX)

          raise Shell::RefusedJob, 'Steam does not run this frame option'
        end

        def output_format(content, image, opts)
          (opts['format'] || content.ext || image['format']).to_s.downcase
        end

        # Count the canvas unless the output is known to ignore it.
        def keeps_canvas?(format, frames)
          !(FORMATS_WITHOUT_CANVAS.include?(format) || (format == 'webp' && frames.size == 1))
        end

        def decoding_size(geometry, image)
          width, height = image['frames'].first&.map(&:to_i)
          return unless image['format'] == 'jpeg' && width.to_i > 0 && height.to_i > 0

          ratio = output_ratio(geometry, width, height)
          return if ratio.nil? || ratio >= 1

          scale = (ratio * 8).ceil / 8.0
          return if scale >= 1

          # Rounding up can make the JPEG decoder select a larger scale.
          size = [(width * scale).floor, (height * scale).floor]
          size if size.all?(&:positive?)
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
