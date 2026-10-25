require 'dragonfly'
require 'dragonfly/image_magick/processors/thumb'

module Locomotive
  module Steam
    class ImageResizerService

      # The Dragonfly geometries ImageMagick runs.
      module Geometry

        THUMB = ::Dragonfly::ImageMagick::Processors::Thumb

        # Reject zero area and explicit zero dimensions with ! or %.
        ZERO_SIZE = /\A0+@\z|\A(?:\d*x0+|0+x\d*)[!%]\z/

        def self.allowed?(geometry)
          case geometry
          when THUMB::RESIZE_GEOMETRY         then !ZERO_SIZE.match?(geometry)
          when THUMB::CROPPED_RESIZE_GEOMETRY then $3.nil? || THUMB::GRAVITIES.key?($3)
          when THUMB::CROP_GEOMETRY           then $3.nil? || $5.nil? # an offset or a gravity, not both
          else false
          end
        end

        def self.check!(geometry)
          raise Shell::RefusedJob, 'Steam does not run this geometry' unless allowed?(geometry)
        end

        # Bound output dimensions and area; before a crop, bound area only.
        def self.within_bounds?(geometry, width, height, canvas: nil, offset: nil)
          resized_within_bounds?(geometry, width, height) &&
            output_within_bounds?(output_size(geometry, width, height, canvas: canvas, offset: offset))
        end

        def self.resized_within_bounds?(geometry, width, height)
          return true unless width.positive? && height.positive?

          area = Locomotive::Steam.configuration.image_resizer_max_area
          sizes(geometry, width, height)[0...-1].all? { |size| size.inject(:*) <= area }
        end

        # The output, as large as the canvas a resize scales with the frame; a crop resets the canvas.
        # The canvas defaults to the frame; an offset counts only for an encoder that may size a canvas from it.
        def self.output_size(geometry, width, height, canvas: nil, offset: nil)
          return [0, 0] unless width.positive? && height.positive?

          output = sizes(geometry, width, height).last
          return output unless THUMB::RESIZE_GEOMETRY.match?(geometry)

          sides = output.zip(canvas || [width, height], [width, height]).map do |side, canvas_side, frame|
            [side, ceil(canvas_side * side, frame)].max
          end
          return sides unless offset && canvas_may_vanish?(width, height, canvas)

          sides.zip(offset_reach(geometry, width, height, offset)).map(&:max)
        end

        # A resize may round a canvas narrower than its frame down to nothing.
        def self.canvas_may_vanish?(width, height, canvas)
          !canvas.nil? && (canvas[0] < width || canvas[1] < height)
        end

        # A conservative bound on the canvas an encoder sizes from a frame's scaled offset and the frame, which
        # wraps a negative sum round to any size; a crop resets the offset.
        def self.offset_reach(geometry, width, height, offset)
          return [0, 0] unless width.positive? && height.positive?

          output = sizes(geometry, width, height).last
          return output unless offset && THUMB::RESIZE_GEOMETRY.match?(geometry)

          output.zip(offset, [width, height]).map do |side, start, frame|
            start.negative? ? Float::INFINITY : ceil(start * side, frame) + side
          end
        end

        # The pixels a resize makes of one frame's own rectangle, before a fill's crop and after; a canvas is no pixels
        # until an encoder fills the frame out to it.
        def self.pixel_areas(geometry, width, height)
          return [0, 0] unless width.positive? && height.positive?

          *before, after = sizes(geometry, width, height)
          [before.sum { |size| size.inject(:*) }, after.inject(:*)]
        end

        def self.output_within_bounds?((width, height))
          configuration = Locomotive::Steam.configuration
          side          = configuration.image_resizer_max_side

          width <= side && height <= side && width * height <= configuration.image_resizer_max_area
        end

        # Upper bounds for resize and crop results.
        def self.sizes(geometry, width, height)
          case geometry
          when THUMB::RESIZE_GEOMETRY
            [resized(geometry, width, height)]
          when THUMB::CROPPED_RESIZE_GEOMETRY
            crop   = [$1.to_i, $2.to_i]
            filled = fill(width, height, *crop.map { |side| side unless side.zero? })
            [filled, cropped(filled, *crop)]
          when THUMB::CROP_GEOMETRY
            [cropped([width, height], $1.to_i, $2.to_i)]
          end
        end

        def self.resized(geometry, width, height)
          return area(width, height, $1.to_i) if geometry =~ /\A(\d+)@\z/

          geometry =~ /\A(\d*)x(\d*)(.?)\z/
          w, h, flag = ($1.to_i unless $1.empty?), ($2.to_i unless $2.empty?), $3
          free_w, free_h = (w unless w == 0), (h unless h == 0)

          case flag
          when '%' then percent(width, height, w, h)
          when '!' then [w || width, h || height]
          when '^' then fill(width, height, free_w, free_h)
          when '>' then shrinks?(width, height, w, h) ? fit(width, height, free_w, free_h) : [width, height]
          when '<' then enlarges?(width, height, w, h) ? fit(width, height, free_w, free_h) : [width, height]
          else fit(width, height, free_w, free_h)
          end
        end

        # A height left out takes the width's percentage; a width left out keeps the source width.
        def self.percent(width, height, w, h)
          [ceil(width * (w || 100), 100), ceil(height * (h || w || 100), 100)]
        end

        # Any side past its own shrinks the image; only every side short of its own enlarges it.
        def self.shrinks?(width, height, w, h)
          (w && width > w) || (h && height > h)
        end

        def self.enlarges?(width, height, w, h)
          (w || h) && (w.nil? || width < w) && (h.nil? || height < h)
        end

        def self.fit(width, height, w, h)
          return [width, height] if w.nil? && h.nil?
          return [w, ceil(height * w, width)] if h.nil? || (w && w * height <= h * width)

          [ceil(width * h, height), h]
        end

        # A side left out takes the other's size.
        def self.fill(width, height, w, h)
          w, h = (w || h), (h || w)
          return [width, height] if w.nil?

          w * height >= h * width ? [w, ceil(height * w, width)] : [ceil(width * h, height), h]
        end

        # Round area-derived dimensions up without floating-point overflow.
        def self.area(width, height, pixels)
          [root_ceil(pixels * width, height), root_ceil(pixels * height, width)]
        end

        def self.root_ceil(numerator, denominator)
          root = Integer.sqrt(numerator / denominator)
          root += 1 if root * root * denominator < numerator
          root
        end

        # A zero side keeps the whole image's.
        def self.cropped((width, height), w, h)
          [w.zero? ? width : [w, width].min, h.zero? ? height : [h, height].min]
        end

        def self.ceil(numerator, denominator)
          (numerator + denominator - 1) / denominator
        end

        private_class_method :resized, :percent, :shrinks?, :enlarges?, :fit, :fill, :area, :root_ceil,
                             :cropped, :ceil

      end

    end
  end
end
