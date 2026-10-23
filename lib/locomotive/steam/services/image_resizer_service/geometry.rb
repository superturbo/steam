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

      end

    end
  end
end
