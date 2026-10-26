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
          check_size_bounds
          check_command_slots

          # Clear earlier rules before installing source checks.
          ::Dragonfly.app(:steam).server.fetch_file_whitelist.patterns.clear
          ::Dragonfly.app(:steam).server.fetch_url_whitelist.patterns.clear

          ::Dragonfly.app(:steam).configure do
            if imagemagick_commands
              plugin :imagemagick, imagemagick_commands
              processor :thumb, Locomotive::Steam::ImageResizerService::Thumb.new
              analyser :steam_image, Locomotive::Steam::ImageResizerService::SourceImage.new

              processor :convert do |content, args|
                Locomotive::Steam::ImageResizerService::ConvertArguments.check!(args)
                ::Dragonfly::ImageMagick::Commands.convert(content, args)
              rescue ::Dragonfly::Shell::CommandFailed => e
                Locomotive::Steam::ImageResizerService::Shell.reraise(e)
              end
            end

            fetch_file_whitelist [Locomotive::Steam::ImageResizerService::LocalSources.new]

            fetch_url_whitelist [Locomotive::Steam::ImageResizerService::RemoteSources.new]

            verify_urls true

            secret key

            url_format '/steam/dynamic/:job/:sha/:basename.:ext'
          end

          ::Dragonfly.logger = Locomotive::Common::Logger

          if imagemagick_commands
            Locomotive::Steam::ImageResizerService::Shell.install(::Dragonfly.app(:steam), timeout: timeout, slots: command_slots)
              .check_policy(convert: imagemagick_commands[:convert_command], identify: imagemagick_commands[:identify_command])
          end
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

        def check_size_bounds
          configuration = Locomotive::Steam.configuration

          %i(image_resizer_max_side image_resizer_max_area).each do |name|
            value = configuration.public_send(name)
            next if value.is_a?(Integer) && value.positive?

            raise ArgumentError, "Steam needs #{name} as a positive whole number of pixels."
          end
        end

        def check_command_slots
          configuration = Locomotive::Steam.configuration
          total    = configuration.image_magick_max_concurrent_commands
          per_site = configuration.image_magick_max_concurrent_commands_per_site
          wait     = configuration.image_magick_command_queue_timeout

          unless total.is_a?(Integer) && total >= 1
            raise ArgumentError, 'Steam needs image_magick_max_concurrent_commands as a whole number, 1 or more.'
          end
          unless per_site.is_a?(Integer) && per_site.between?(1, total)
            raise ArgumentError, 'Steam needs image_magick_max_concurrent_commands_per_site as a whole number from 1 to ' \
                                 'image_magick_max_concurrent_commands.'
          end
          return if wait.is_a?(Numeric) && wait.real? && wait.finite? && wait >= 0

          raise ArgumentError, 'Steam needs image_magick_command_queue_timeout as a finite number of seconds, 0 or more.'
        end

        def command_slots
          configuration = Locomotive::Steam.configuration

          ImageResizerService::CommandSlots.new(
            directory: lock_directory(configuration.image_magick_command_lock_path),
            total:     configuration.image_magick_max_concurrent_commands,
            per_site:  configuration.image_magick_max_concurrent_commands_per_site,
            wait:      configuration.image_magick_command_queue_timeout
          )
        end

        # A directory of the application user's own, which no one else can use, made when missing.
        def lock_directory(path)
          begin
            Dir.mkdir(path.to_s, 0o700)
          rescue Errno::EEXIST
            nil
          end
          stat = File.lstat(path.to_s)
          return path if stat.directory? && stat.owned? && (stat.mode & 0o077).zero?

          raise ArgumentError, "Steam needs image_magick_command_lock_path as a directory of its own user that no one else " \
                               "can use, not #{path.inspect}."
        rescue SystemCallError
          raise ArgumentError, "Steam cannot make image_magick_command_lock_path #{path.inspect}."
        end

        def check_remote_source_prefix
          prefix = Locomotive::Steam.configuration.image_resizer_remote_source_prefix
          return if prefix.nil? || ImageResizerService::RemoteSources.prefix?(prefix)

          raise ArgumentError, 'Steam needs image_resizer_remote_source_prefix as an http or https URL prefix ' \
                               'without a user, a query or a fragment.'
        end

        def find_imagemagick_commands
          convert   = ENV['IMAGE_MAGICK_CONVERT'] || `which magick`.strip.presence || `which convert`.strip.presence || '/usr/local/bin/convert'
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
