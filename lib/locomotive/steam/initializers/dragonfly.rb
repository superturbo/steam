require 'dragonfly'

module Locomotive
  module Steam
    module Initializers

      class Dragonfly

        def run
          # need to be called outside of the configure method
          imagemagick_commands = find_imagemagick_commands
          key = signing_key

          ::Dragonfly.app(:steam).configure do
            if imagemagick_commands
              plugin :imagemagick, imagemagick_commands
            end

            processor :convert do |content, args|
              ::Dragonfly::ImageMagick::Commands.convert(content, args)
            end

            verify_urls true

            secret key

            url_format '/steam/dynamic/:job/:sha/:basename.:ext'

            fetch_file_whitelist /public/

            fetch_url_whitelist /.+/
          end

          ::Dragonfly.logger = Locomotive::Common::Logger
        end

        def signing_key
          configuration = Locomotive::Steam.configuration
          key = configuration.image_resizer_secret

          unless key.nil? || key.is_a?(String)
            raise ArgumentError, "Steam needs the image_resizer_secret as text, got #{key.class}."
          end

          return key unless key.blank? || key == 'please change it'
          return SecureRandom.hex(32) if configuration.mode == :test

          raise ArgumentError, 'Steam needs an image_resizer_secret outside test mode; ' \
                               "a blank value or 'please change it' is not one."
        end

        def find_imagemagick_commands
          convert   = ENV['IMAGE_MAGICK_CONVERT'] || `which convert`.strip.presence || '/usr/local/bin/convert'
          identify  = ENV['IMAGE_MAGICK_IDENTIFY'] || `which identify`.strip.presence || '/usr/local/bin/identify'

          if File.exist?(convert)
            { convert_command: convert, identify_command: identify }
          else
            missing_image_magick
            nil
          end
        end

        def missing_image_magick
          Locomotive::Common::Logger.warn <<-EOF
[Dragonfly] !disabled!
[Dragonfly] If you want to take full benefits of all the features in Locomotive Steam, we recommend you to install ImageMagick. Check out the documentation here: http://doc.locomotivecms.com.
EOF
        end

      end
    end
  end
end

Locomotive::Steam::Initializers::Dragonfly.new.run
