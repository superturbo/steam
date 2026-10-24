module Locomotive
  module Steam
    class ImageResizerService

      # The format of an image, and the size, canvas and offset of each of its frames, in one identify.
      class SourceImage

        def call(content)
          identify = content.env[:identify_command] || 'identify'
          format   = '%m %w %h %W %H %X %Y\\n'
          lines    = content.shell_eval { |path| "#{identify} -ping -format '#{format}' #{path}" }.lines.map(&:split)

          {
            'format' => lines.first&.first.to_s.downcase,
            'frames' => lines.map { |_, *sizes| sizes.map(&:to_i) }
          }
        end

      end

    end
  end
end
