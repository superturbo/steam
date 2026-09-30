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

      # No shared copy under no-store or private, and none Steam could reuse without the validation no-cache asks for.
      NOT_SHARED_DIRECTIVES     = %w(no-cache no-store private).freeze

      # Stores already warned about, so the warning does not repeat on every request.
      UNSUPPORTED_STORES        = ObjectSpace::WeakMap.new

      # Steam's own Vary. Its locale comes from the URL, so a cached page must not otherwise render by Accept-Language.
      SHAREABLE_VARY            = %w(accept-language).freeze

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

          # Keep responses that use a session or set a cookie private even if rendering overrides Cache-Control.
          had_session = session.present?
          response    = self.next
          keep_private(response) if had_session || session.present? || sets_cookie?(response)
        end
      end

      private

      def fetch_cached_response(key)
        log("Cache key = #{key.inspect}")
        # The configured policy decides the read. The write also needs the response's own.
        shared = page_store && shareable?(cache_control, cache_vary)
        stored = stored_copy(key) if shared

        if stored
          log('Cache HIT')
          not_modified?(stored) ? not_modified(stored) : stored
        else
          log('Cache MISS')
          self.next.tap do |response|
            # Rendering may create a session or set a cookie. Check again before storing.
            if session.present? || sets_cookie?(response) || !CACHEABLE_RESPONSE_CODES.include?(response.first.to_i)
              keep_private(response)
            elsif request.get? && shared && shareable?(response[1]['cache-control'], response[1]['vary'])
              # A template can tell HEAD from GET, so only a GET response is stored.
              add_etag(response)
              page_store.write(key, marshal(response), version: cache_version, expires_in: lifetime(response[1]['cache-control']))
            end
          end
        end
      end

      # Do not replay Set-Cookie from an older stored copy.
      def stored_copy(key)
        marshaled = page_store.read(key, version: cache_version)
        stored    = Marshal.load(marshaled) if marshaled
        stored unless stored.nil? || stored[1].key?('set-cookie')
      end

      # Store only responses Steam may reuse for a bounded time without varying by another header.
      def shareable?(cache_control, vary)
        (directive_names(cache_control) & NOT_SHARED_DIRECTIVES).empty? &&
          lifetime(cache_control).to_i.positive? &&
          (Array(vary).join(',').split(',').map { |name| name.strip.downcase } - SHAREABLE_VARY).empty?
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
        !sets_cookie? &&
        !live_editing? &&
        site.try(:cache_enabled) &&
        page.try(:cache_enabled) &&
        is_redirect_url?
      end

      def sets_cookie?(response = nil)
        env['steam.cookies'].present? || (response && response[1].key?('set-cookie'))
      end

      def cache_key
        "steam/page/#{Digest::SHA256.hexdigest("#{site._id}\n#{request.url}")}"
      end

      # Never empty: ActiveSupport reads an entry without a version as a match.
      # expand_cache_key puts the deployment's generation (RAILS_CACHE_ID or RAILS_APP_VERSION) first.
      def cache_version
        ActiveSupport::Cache.expand_cache_key("#{Locomotive::Steam::VERSION}/#{site.last_modified_at&.strftime('%s.%N') || 'none'}")
      end

      # Pages are kept only in an ActiveSupport::Cache::Store, whose API reads another version as a miss.
      def page_store
        return cache if cache.is_a?(ActiveSupport::Cache::Store)

        unless UNSUPPORTED_STORES.key?(cache)
          UNSUPPORTED_STORES[cache] = true
          Locomotive::Common::Logger.warn "Steam's page cache is off: #{cache.class} is not an ActiveSupport::Cache::Store"
        end
        nil
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

      def directive_names(cache_control)
        directives(cache_control).map(&:first)
      end

      # Name and argument pairs, ignoring commas inside quoted arguments.
      def directives(cache_control)
        cache_control.to_s.gsub(/"(?:[^"\\]|\\.)*"/, '""').split(',').map do |directive|
          name, argument = directive.split('=', 2)
          [name.strip.downcase, argument&.strip]
        end
      end

      # The shared lifetime in seconds: s-maxage, else max-age. Nil when absent, malformed or conflicting.
      def lifetime(cache_control)
        all = directives(cache_control)

        %w(s-maxage max-age).each do |name|
          arguments = all.select { |directive, _| directive == name }.map(&:last).uniq
          next if arguments.empty?

          return arguments.size == 1 && arguments.first.to_s.match?(/\A\d+\z/) ? arguments.first.to_i : nil
        end
        nil
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
