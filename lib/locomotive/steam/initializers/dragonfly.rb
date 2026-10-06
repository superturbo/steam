require 'dragonfly'

module Locomotive
  module Steam
    module Initializers

      class Dragonfly

        def run
          # need to be called outside of the configure method
          imagemagick_commands = find_imagemagick_commands
          key = signing_key
          timeout = command_timeout
          check_remote_source_prefix

          # Clear earlier rules before installing source checks.
          ::Dragonfly.app(:steam).server.fetch_file_whitelist.patterns.clear
          ::Dragonfly.app(:steam).server.fetch_url_whitelist.patterns.clear

          ::Dragonfly.app(:steam).configure do
            if imagemagick_commands
              plugin :imagemagick, imagemagick_commands
              processor :thumb, Locomotive::Steam::ImageResizerService::Thumb.new

              processor :convert do |content, args|
                ::Dragonfly::ImageMagick::Commands.convert(content, args)
              end
            end

            fetch_file_whitelist [Locomotive::Steam::ImageResizerService::LocalSources.new]

            fetch_url_whitelist [Locomotive::Steam::ImageResizerService::RemoteSources.new]

            verify_urls true

            secret key

            url_format '/steam/dynamic/:job/:sha/:basename.:ext'
          end

          if imagemagick_commands
            Locomotive::Steam::ImageResizerService::Shell.install(::Dragonfly.app(:steam), timeout: timeout)
          end

          ::Dragonfly.logger = Locomotive::Common::Logger
        end

        def command_timeout
          timeout = Locomotive::Steam.configuration.image_magick_command_timeout
          return timeout if timeout.is_a?(Numeric) && timeout.real? && timeout.finite? && timeout.positive?

          raise ArgumentError, 'Steam needs image_magick_command_timeout as a positive number of seconds.'
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

        def check_remote_source_prefix
          prefix = Locomotive::Steam.configuration.image_resizer_remote_source_prefix
          return if prefix.nil? || ImageResizerService::RemoteSources.prefix?(prefix)

          raise ArgumentError, 'Steam needs image_resizer_remote_source_prefix as an http or https URL prefix ' \
                               'without a user, a query or a fragment.'
        end

        def find_imagemagick_commands
          convert   = ENV['IMAGE_MAGICK_CONVERT'] || `which convert`.strip.presence || '/usr/local/bin/convert'
          identify  = ENV['IMAGE_MAGICK_IDENTIFY'] || `which identify`.strip.presence || '/usr/local/bin/identify'

          if File.exist?(convert)
            raise "Steam resizes with ImageMagick's identify, which is not found: #{identify}" unless File.exist?(identify)

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
