require 'tmpdir'

module Locomotive
  module Steam

    class Configuration

      # Mainly used in the liquid templates (variable name: {{ mode }})
      # to distinguish the page rendered in Wagon (:test) or in the Engine.
      #
      # default: :production
      #
      attr_accessor :mode
      def mode; @mode || :production; end

      # Steam needs an adapter in order to fetch the site content (site itself, pages, content entries, ...etc).
      # By default, Steam is shipped with 2 adapters:
      #     - Filesystem (options: path). the path option should point to the root path of the site
      #     - MongoDB (options: database, hosts)
      #
      # default: { name: :filesytem, path: nil }
      #
      attr_accessor :adapter

      # Manage the list of middlewares used by the rack stack.
      #
      # Example:
      #
      #   Locomotive::Steam.configure do |config|
      #     ...
      #     config.middleware.remove Rack::Lint
      #     ...
      #     config.middleware.insert_after Middleware::Locale, MySlugMiddleware, answer: 42
      #     ...
      #   end
      #
      attr_accessor :middleware
      def middleware
        @middleware ||= Middlewares::StackProxy.new(&Locomotive::Steam::Server.default_middlewares)
      end

      # Add the checksum of a theme asset at the end of its path to allow public caching.
      #
      # default: false (disabled)
      #
      attr_accessor :theme_assets_checksum
      def theme_assets_checksum; @theme_assets_checksum.nil? ? false : @theme_assets_checksum; end

      # Enable serving of images, stylesheets, and JavaScripts from an asset server.
      # Useful if a CDN is used to serve assets.
      # A callable receives the request and site.
      # On cached pages, its result must depend only on the site and request URL.
      #
      # default: nil
      #
      attr_accessor :asset_host

      # The public origin of a site (scheme://host[:port]) in its password reset links.
      # A callable receives the site; a host serving several sites passes one.
      #
      # default: nil
      #
      attr_accessor :public_origin

      # Tell if Steam has to also serve static (images) or dynamic (SASS, Coffeescript) assets.
      #
      # default: true
      #
      attr_accessor :serve_assets
      def serve_assets; @serve_assets.nil? ? true : @serve_assets; end

      # Root directory for local resize sources.
      # Steam also serves assets from it when serve_assets is enabled.
      #
      # default: nil
      #
      attr_accessor :asset_path

      # Signs the resize URLs, e.g. a key from `openssl rand -hex 32`.
      #
      # default: nil (required outside test mode)
      #
      attr_accessor :image_resizer_secret

      # Public URL prefix of remote resize sources (not a storage API endpoint), e.g. 'https://cdn.example.com/sites/'.
      #
      # default: nil (no remote source)
      #
      attr_accessor :image_resizer_remote_source_prefix

      # Largest side and area of a resize output, for each frame and a canvas the output keeps;
      # the resize a fill makes before its crop keeps the area alone.
      #
      # default: 5760 and 25_000_000
      #
      attr_accessor :image_resizer_max_side, :image_resizer_max_area
      def image_resizer_max_side; @image_resizer_max_side.nil? ? 5760 : @image_resizer_max_side; end
      def image_resizer_max_area; @image_resizer_max_area.nil? ? 25_000_000 : @image_resizer_max_area; end

      # Timeout for one ImageMagick command once it has its slots, not the whole resize job.
      #
      # default: 30
      #
      attr_accessor :image_magick_command_timeout
      def image_magick_command_timeout; @image_magick_command_timeout.nil? ? 30 : @image_magick_command_timeout; end

      # ImageMagick commands that may run at once in the processes sharing image_magick_command_lock_path, and how many
      # of them one rendering site may run.
      #
      # default: 5 and 2
      #
      attr_accessor :image_magick_max_concurrent_commands, :image_magick_max_concurrent_commands_per_site
      def image_magick_max_concurrent_commands; @image_magick_max_concurrent_commands.nil? ? 5 : @image_magick_max_concurrent_commands; end
      def image_magick_max_concurrent_commands_per_site
        @image_magick_max_concurrent_commands_per_site.nil? ? 2 : @image_magick_max_concurrent_commands_per_site
      end

      # Seconds a command may wait for its slots, in no order among the commands waiting, before Steam answers 503.
      # A waiting command holds its request's thread; keep it below the timeout of a proxy in front.
      #
      # default: 10
      #
      attr_accessor :image_magick_command_queue_timeout
      def image_magick_command_queue_timeout; @image_magick_command_queue_timeout.nil? ? 10 : @image_magick_command_queue_timeout; end

      # Directory of the command slots' lock files, private to the application user and outside a release directory.
      #
      # default: steam-image-magick-<user id> in the system temporary directory
      #
      attr_accessor :image_magick_command_lock_path
      def image_magick_command_lock_path
        @image_magick_command_lock_path.nil? ? File.join(Dir.tmpdir, "steam-image-magick-#{Process.euid}") : @image_magick_command_lock_path
      end

      # Enable CSRF protection for entry submissions, authentication actions and unlocking private sites.
      #
      # default: true
      #
      attr_accessor :csrf_protection
      def csrf_protection; @csrf_protection.nil? ? true : @csrf_protection; end

      # Options for the store of Moneta (Session)
      #
      # default: { store: Moneta.new(:Memory, expires: true) }
      #
      attr_accessor :moneta
      def moneta; @moneta.nil? ? { store: Moneta.new(:Memory, expires: true) } : @moneta; end

      # Render a 404 page if no site has been found.
      # If Steam is embedded in another app, it's better to let the app handle
      # the no site case.
      #
      # default: true
      #
      attr_accessor :render_404_if_no_site
      def render_404_if_no_site; @render_404_if_no_site.nil? ? true : @render_404_if_no_site; end

      # Log file
      #
      # default: nil (STDOUT)
      #
      attr_accessor :log_file

      # Log level
      #
      # default: ::Logger::INFO
      #
      attr_accessor :log_level
      def log_level; @log_level || ::Logger::INFO; end

      # Lambda called once a Services instance has been built.
      # It is used when we want to change one of the services
      #
      # Example:
      #
      # Locomotive::Steam.configure do |config|
      #
      #   config.services_hook = -> (services) {
      #     require 'my_custom_site_finder'
      #     services.site_finder = MyCustomSiteFinder.new
      #   }
      #
      # end
      #
      # default: nil
      #
      attr_accessor :services_hook

    end

  end
end
