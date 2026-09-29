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

      NOT_MODIFIED_HEADERS      = %w(cache-control content-location date etag expires vary).freeze

      ENTITY_TAG                = %r{\A(?:W/)?"[^"]*"\z}

      def _call
        if cacheable?
          key = cache_key

          # tell the CDN (or any proxy) how long it may keep the page and what the page varies on
          env['steam.cache_control']        = cache_control
          env['steam.cache_vary']           = cache_vary

          # we don't want to render twice the page
          @next_response = fetch_cached_response(key)
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
          stored = Marshal.load(marshaled)
          not_modified?(stored) ? not_modified(stored) : stored
        else
          log('Cache MISS')
          self.next.tap do |response|
            # Rendering may create a session. Check again before storing.
            if session.present? || !CACHEABLE_RESPONSE_CODES.include?(response.first.to_i)
              keep_private(response)
            elsif request.get?
              # A template can tell HEAD from GET, so only a GET response is stored.
              add_etag(response)
              cache.write(key, marshal(response))
            end
          end
        end
      end

      # Only a stored 200 answers 304. A tag with a comma inside its quotes matches nothing.
      def not_modified?(response)
        code, headers = response
        return false unless code.to_i == 200

        if_none_match = env['HTTP_IF_NONE_MATCH'].to_s.strip
        return true if if_none_match == '*'

        tags = if_none_match.split(',').map(&:strip).reject(&:empty?)
        return false unless tags.all?(ENTITY_TAG)

        tags.map { |tag| tag.delete_prefix('W/') }.include?(headers['etag']&.delete_prefix('W/'))
      end

      # Same digest as Rack::ETag.
      def add_etag(response)
        _, headers, body = response
        return if headers.key?('etag')

        digest = nil
        body.each { |part| (digest ||= Digest::SHA256.new) << part unless part.empty? }
        headers['etag'] = %(W/"#{digest.hexdigest[0, 32]}") if digest
      end

      def not_modified(response)
        [304, response[1].slice(*NOT_MODIFIED_HEADERS), []]
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
        site = env['steam.site']
        key  = "#{Locomotive::Steam::VERSION}/site/#{site._id}/#{site.last_modified_at&.strftime('%s.%N')}/url/#{request.url}"
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
        headers.delete('vary') if headers['vary'] == env['steam.cache_vary']
        env['steam.cache_vary'] = nil
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

      def cache
        services.cache
      end

    end

  end
end
