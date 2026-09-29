module Locomotive::Steam
  module Middlewares

    class Cache < ThreadSafe

      include Concerns::Helpers

      CACHEABLE_RESPONSE_CODES  = [200, 301, 404, 410].freeze

      CACHEABLE_REQUEST_METHODS = %w(GET HEAD).freeze

      DEFAULT_CACHE_CONTROL     = 'max-age=0, s-maxage=3600, public, must-revalidate'.freeze

      DEFAULT_CACHE_VARY        = 'Accept-Language'.freeze

      NO_CACHE_CONTROL          = 'max-age=0, private, must-revalidate'.freeze

      NO_STORE_CACHE_CONTROL    = 'no-store'.freeze

      def _call
        if cacheable?
          key = cache_key

          # A client holding the current ETag gets a 304 response
          if stale?(key)
            render_response(nil, 304, nil)
            return
          end

          # we have to tell the CDN (or any proxy) what the expiration & validation strategy are
          env['steam.cache_control']        = cache_control
          env['steam.cache_vary']           = cache_vary
          env['steam.cache_etag']           = key

          # retrieve the response from the cache.
          response = fetch_cached_response(key)

          keep_private(response) unless CACHEABLE_RESPONSE_CODES.include?(response.first.to_i)

          # we don't want to render twice the page
          @next_response = response
        else
          env['steam.cache_control']  = private_cache_control

          # Keep session responses private even if rendering overrides Cache-Control.
          had_session = session.present?
          response    = self.next
          keep_private(response) if had_session || session.present?
        end
      end

      private

      def fetch_cached_response(key)
        log("Cache key = #{key.inspect}")
        if marshaled = cache.read(key)
          log('Cache HIT')
          Marshal.load(marshaled)
        else
          log('Cache MISS')
          self.next.tap do |response|
            # Rendering may create a session. Check again before storing.
            if session.present?
              keep_private(response)
            elsif CACHEABLE_RESPONSE_CODES.include?(response.first.to_i)
              cache.write(key, marshal(response))
            end
          end
        end
      end

      def cacheable?
        CACHEABLE_REQUEST_METHODS.include?(env['REQUEST_METHOD']) &&
        session.blank? &&
        !live_editing? &&
        site.try(:cache_enabled) &&
        page.try(:cache_enabled) &&
        is_redirect_url?
      end

      def cache_key
        site, path, query = env['steam.site'], env['PATH_INFO'], env['QUERY_STRING']
        key = "#{Locomotive::Steam::VERSION}/site/#{site._id}/#{site.last_modified_at.to_i}/page/#{path}/#{query}"
        Digest::MD5.hexdigest(key)
      end

      def cache_control
        page.try(:cache_control).presence || site.try(:cache_control).presence || DEFAULT_CACHE_CONTROL
      end

      def cache_vary
        page.try(:cache_vary).presence || site.try(:cache_vary).presence || DEFAULT_CACHE_VARY
      end

      def is_redirect_url?
        return false if page.nil?
        page.try(:redirect_url).blank?
      end

      # Remove headers matching Steam's shared-cache values.
      def keep_private(response)
        headers = response[1]

        env['steam.cache_control'] = headers['cache-control'] = private_cache_control(headers['cache-control'])
        headers.delete('etag') if headers['etag'] == env['steam.cache_etag']
        headers.delete('vary') if headers['vary'] == env['steam.cache_vary']
        env['steam.cache_vary'] = env['steam.cache_etag'] = nil
      end

      # Replace shared-cache directives, preserving no-store and no-transform.
      def private_cache_control(answered = nil)
        names  = directive_names(cache_control) + directive_names(answered)
        policy = names.include?('no-store') ? NO_STORE_CACHE_CONTROL : NO_CACHE_CONTROL

        names.include?('no-transform') ? "#{policy}, no-transform" : policy
      end

      # Ignore commas inside quoted directive arguments.
      def directive_names(cache_control)
        cache_control.to_s.gsub(/"(?:[^"\\]|\\.)*"/, '""').split(',').map do |directive|
          directive.split('=', 2).first.strip.downcase
        end
      end

      def marshal(response)
        code, headers, body = response

        # only keep string value headers
        _headers = headers.reject { |key, val| !val.respond_to?(:to_str) }

        Marshal.dump([code, _headers, body])
      end

      def stale?(key)
        env['HTTP_IF_NONE_MATCH'] == key
      end

      def cache
        services.cache
      end

    end

  end
end
