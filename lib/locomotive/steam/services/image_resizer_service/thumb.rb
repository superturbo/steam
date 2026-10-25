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

        # Orientations that rotate or mirror pixels.
        REORIENTED = %w(TopRight BottomRight BottomLeft LeftTop RightTop RightBottom LeftBottom).freeze

        # Orientations that swap width and height.
        TRANSPOSED = %w(LeftTop RightTop RightBottom LeftBottom).freeze

        # ImageMagick reads a frame index as a floating-point number, exact up to 2**53.
        MAX_FRAME_INDEX = 2**53

        # Their encoded image leaves the canvas out: dropped, or kept by PNG as metadata alone.
        FORMATS_WITHOUT_CANVAS = %w(jpg jpeg png png8 png24 png32 png48 png64 tif tiff bmp avif psd ico).freeze

        # Their encoder keeps each frame's canvas as it is, building none of its own.
        FORMATS_WITH_FRAME_CANVASES = %w(miff).freeze

        # Their encoder writes each frame of a sequence as its own rectangle; another may fill the frames out to one
        # canvas, as ImageMagick coalesces them for WebP.
        FORMATS_WRITING_FRAME_RECTANGLES = %w(gif gif87 miff).freeze

        # The sizes a JPEG decodes to, k/8 of each side rounded up, that are no smaller than the size asked for.
        def self.decoded_sizes(width, height, (least_width, least_height))
          (1..8).map { |eighths| [(width * eighths + 7) / 8, (height * eighths + 7) / 8] }
                .select { |w, h| w >= least_width && h >= least_height }
        end

        def call(content, geometry, opts = {})
          Geometry.check!(geometry)

          decode = opts['decode']
          raise Shell::RefusedJob, 'Steam does not run this decode option' unless decode.nil? || decode == DECODE

          orient = opts['orient']
          raise Shell::RefusedJob, 'Steam does not run this orient option' unless orient.nil? || orient == true

          validate!(opts['format'], &is_word)
          opts = opts.merge('frame' => frame_index(opts['frame'])) unless opts['frame'].nil?

          image = content.analyse(:steam_image)
          size  = decoding_size(geometry, image, orient) if decode
          if orient
            # Bound the actual oriented image before resizing.
            frames = SourceImage.oriented(content, opts['frame'], decoding_define(size))['frames']
            repage = repage?(frames)
            check_sizes!(geometry, repage ? repaged(frames) : frames, output_format(content, image, opts))
          else
            check_sizes!(geometry, read_frames(image, opts['frame']), output_format(content, image, opts), size)
            return super(content, geometry, opts) if decode.nil?
          end

          args = [('-auto-orient' if orient), ('+repage' if repage), args_for_geometry(geometry)].compact.join(' ')
          ::Dragonfly::ImageMagick::Commands.convert(content, args, {
            'format'     => opts['format'],
            'frame'      => opts['frame'],
            'input_args' => decoding_define(size)
          })
        rescue ::Dragonfly::Shell::CommandFailed => e
          Shell.reraise(e)
        end

        private

        # Every frame the job reads, at each size it may decode to.
        def check_sizes!(geometry, frames, format, decoding_size = nil)
          canvas = keeps_canvas?(format, frames)
          # An encoder that keeps a canvas may build its own: one shared across frames, or one sized from an offset.
          builds = canvas && !FORMATS_WITH_FRAME_CANVASES.include?(format)

          choices = frames.map do |frame|
            decoded(frame, decoding_size).map do |choice|
              [*choice['size'], { canvas: (choice['canvas'] if canvas), offset: (choice['offset'] if builds) }]
            end
          end
          inputs = choices.flatten(1)

          outputs = inputs.map { |w, h, placement| Geometry.output_size(geometry, w, h, **placement) }
          shared  = shared_canvas(geometry, inputs, outputs) if builds && outputs.size > 1
          outputs << shared if shared

          unless inputs.any? && inputs.all? { |w, h| Geometry.resized_within_bounds?(geometry, w, h) } &&
                 outputs.all? { |output| Geometry.output_within_bounds?(output) }
            raise Shell::RefusedJob, 'Steam does not resize to this size'
          end

          filled_to = shared unless FORMATS_WRITING_FRAME_RECTANGLES.include?(format)
          check_sequence!(geometry, choices, filled_to) if choices.size > 1
        end

        # The frames of a sequence together, each at the largest size it may decode to: their outputs, each as large as
        # the canvas they share for an encoder that may fill them out to it, and apart from them the resizes a fill
        # makes before its crop.
        def check_sequence!(geometry, choices, filled_to)
          largest = choices.map do |sizes|
            areas = sizes.map { |width, height, _| Geometry.pixel_areas(geometry, width, height) }
            [areas.map(&:first).max.to_i, filled_to ? filled_to.inject(:*) : areas.map(&:last).max.to_i]
          end
          area = Locomotive::Steam.configuration.image_resizer_max_area
          return if largest.transpose.all? { |totals| totals.sum <= area }

          raise Shell::RefusedJob, 'Steam does not resize a sequence this large'
        end

        # The frames a job reads: the one it names, or every frame when ImageMagick ignores an index past them.
        def read_frames(image, index)
          frame = image['frames'][index] unless index.nil?
          frame ? [frame] : image['frames']
        end

        # Reset transformed single-image canvases without moving sequence frames.
        def repage?(frames)
          frames.one? && REORIENTED.include?(frames.first['source_orientation'])
        end

        def repaged(frames)
          frames.map { |frame| frame.merge('canvas' => frame['size'], 'offset' => [0, 0]) }
        end

        def decoding_define(size)
          "-define jpeg:size=#{size.join('x')}" if size
        end

        # The sizes a JPEG frame may decode to, each its own canvas.
        def decoded(frame, decoding_size)
          return [frame] unless decoding_size

          self.class.decoded_sizes(*frame['size'], decoding_size).map do |size|
            frame.merge('size' => size, 'canvas' => size, 'offset' => [0, 0])
          end
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

        # Compute the ratio after orientation; request JPEG decoding in encoded dimensions.
        def decoding_size(geometry, image, orient)
          first = image['frames'].first || {}
          width, height = first['size']
          return unless image['format'] == 'jpeg' && width.to_i > 0 && height.to_i > 0

          turns = orient && TRANSPOSED.include?(first['orientation'])
          ratio = turns ? output_ratio(geometry, height, width) : output_ratio(geometry, width, height)
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
