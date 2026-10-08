require 'shellwords'

module Locomotive
  module Steam
    class ImageResizerService

      module ConvertArguments

        OPTIONS = {
          '-quality'     => [/\A(?:100|[1-9]?\d)\z/, 2], # quality, optimize
          '-strip'       => [nil, 2],                     # strip, optimize
          '-interlace'   => [/\APlane\z/, 2],             # progressive, optimize
          '-auto-orient' => [nil, 1]                      # auto_orient
        }.freeze

        def self.allowed?(arguments)
          return false unless arguments.is_a?(String)

          words, seen = Shellwords.split(arguments), Hash.new(0)
          until words.empty?
            name = words.shift
            value_pattern, max_occurrences = OPTIONS[name]
            return false unless max_occurrences && (seen[name] += 1) <= max_occurrences
            return false if value_pattern && !value_pattern.match?(words.shift.to_s)
          end
          true
        rescue ArgumentError
          false
        end

        def self.check!(arguments)
          raise Shell::RefusedJob, 'Steam does not run these ImageMagick arguments' unless allowed?(arguments)
        end

      end

    end
  end
end
