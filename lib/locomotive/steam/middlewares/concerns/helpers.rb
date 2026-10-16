module Locomotive::Steam
  module Middlewares
    module Concerns
      module Helpers

        HTML_CONTENT_TYPE = 'text/html'.freeze

        HTML_MIME_TYPES   = [nil, 'text/html', 'application/x-www-form-urlencoded', 'multipart/form-data'].freeze

        CACHE_HEADERS     = {
          'steam.cache_control'       => 'cache-control',
          'steam.cache_vary'          => 'vary'
        }.freeze

        def html?
          HTML_MIME_TYPES.include?(self.request.media_type) &&
          !self.request.xhr? &&
          !self.json?
        end

        def json?
          self.request.media_type == 'application/json' || File.extname(self.request.path) == '.json'
        end

        def render_response(content, code = 200, type = nil)
          base_headers = { 'content-type' => type || HTML_CONTENT_TYPE }

          CACHE_HEADERS.each do |key, http_name|
            base_headers[http_name] = env[key] if env[key]
          end

          _headers = env['steam.headers'] || {}
          inject_cookies(_headers)

          @next_response = [code, base_headers.merge(_headers), [content].compact]
        end

        def redirect_to(location, type = 301)
          _location = mounted_on && !location.starts_with?(mounted_on) && (location =~ Locomotive::Steam::IsHTTP).nil? ? "#{mounted_on}#{location}" : location

          self.debug_log "Redirected to #{_location}".blue

          headers = { 'content-type' => HTML_CONTENT_TYPE, 'location' => _location }
          inject_cookies(headers)

          @next_response = [type, headers, []]
        end

        def inject_cookies(headers)
          _cookies = env['steam.cookies'] || {}
          _cookies.each do |key, vals|
            Rack::Utils.set_cookie_header!(headers, key, vals.symbolize_keys!)
          end
        end

        def modify_path(path = nil, &block)
          path ||= env['steam.path']

          segments = path.split('/')
          yield(segments) if block_given?
          path = segments.join('/')

          path = '/' if path.blank?
          path += "?#{request.query_string}" unless request.query_string.empty?
          path
        end

        # make sure the location passed in parameter doesn't
        # include the "mounted_on" parameter.
        # If so, returns the location without the "mounted_on" string.
        def make_local_path(location)
          return location if mounted_on.blank?
          location.gsub(Regexp.new('^' + mounted_on), '')
        end

        def mounted_on
          request.env['steam.mounted_on']
        end

        def redirect_location(value, name)
          location = value.to_s
          return if location.blank?
          return location if local_path?(location) || request_origin_url?(location)

          Locomotive::Common::Logger.warn "[#{self.class.name.to_s.demodulize}] Refused the #{name}"
          nil
        end

        def local_request_path
          local_path?(request.path_info) ? request.path_info : '/'
        end

        def local_path?(location)
          location.match?(%r{\A/(?![/\\])[^\s\x00-\x1F\x7F]*\z})
        end

        # Reject URLs that redirect_to would treat as relative.
        def request_origin_url?(location)
          return false unless location.match?(Locomotive::Steam::IsHTTP)

          uri = URI.parse(location)
          uri.userinfo.nil? && "#{uri.scheme}://#{uri.host}#{":#{uri.port}" unless uri.port == uri.default_port}".casecmp?(request.base_url)
        rescue URI::InvalidURIError
          false
        end

        def log(msg, offset = 2)
          Locomotive::Common::Logger.info (' ' * offset) + msg
        end

        def debug_log(msg, offset = 2)
          Locomotive::Common::Logger.debug (' ' * offset) + msg
        end

      end
    end
  end
end
