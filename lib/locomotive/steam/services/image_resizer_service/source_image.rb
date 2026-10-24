module Locomotive
  module Steam
    class ImageResizerService

      # The format of an image and the size, canvas, offset and orientation of each frame.
      class SourceImage

        FORMAT = '%m %w %h %W %H %X %Y %[orientation]'.freeze

        def call(content)
          identify = content.env[:identify_command] || 'identify'
          self.class.parse(content.shell_eval { |path| "#{identify} -ping -format '#{FORMAT}\\n' #{path}" })
        end

        # Full decoding reveals orientation metadata a ping may omit.
        def self.oriented(content, frame, input_args)
          convert = content.env[:convert_command] || 'convert'
          index   = "[#{Integer(frame)}]" unless frame.nil?
          parse(content.shell_eval do |path|
            "#{convert} #{input_args} #{path}#{index} -set steam:orientation '%[orientation]' -auto-orient " \
              "-format '#{FORMAT} %[steam:orientation]\\n' info:"
          end)
        end

        def self.parse(output)
          lines = output.lines.map(&:split)

          {
            'format' => lines.first&.first.to_s.downcase,
            'frames' => lines.map do |_, width, height, canvas_width, canvas_height, x, y, orientation, source_orientation|
              { 'size'   => [width.to_i, height.to_i], 'canvas' => [canvas_width.to_i, canvas_height.to_i],
                'offset' => [x.to_i, y.to_i], 'orientation' => orientation, 'source_orientation' => source_orientation }
            end
          }
        end

      end

    end
  end
end
