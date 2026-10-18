module Locomotive::Steam
  module Middlewares

    # Redirects (301) a request matching a rule among the site's url_redirections to its new URL.
    class UrlRedirection < ThreadSafe

      include Concerns::Helpers

      PARAM               = /:([a-z][a-z0-9_]*)/
      TARGET_PARTS        = %r{\A((?:[a-z][a-z0-9+.-]*:)?//[^/?#]+)?([^?#]*)(\?[^#]*)?(.*)\z}im
      WITHOUT_ORIGIN      = %r{\A(?![a-z][a-z0-9+.-]*:)(?![/\\]{2})}i
      NO_SPACE_OR_CONTROL = /\A[^\s\x00-\x1F\x7F]*\z/

      def _call
        if url = redirect_url
          emit_event

          redirect_to url
        end
      end

      protected

      def requested_url
        request.env['locomotive.path'] || request.fullpath
      end

      def emit_event
        ActiveSupport::Notifications.instrument('steam.serve.url_redirection', {
          site_id:  site._id,
          url:      requested_url
        })
      end

      def redirect_url
        return false if site.url_redirections.nil? || site.url_redirections.size == 0

        redirections_hash = site.url_redirections.to_h

        redirections_hash[requested_url] || find_dynamic_url_redirection(redirections_hash)
      end

      def find_dynamic_url_redirection(redirections_hash)
        path = request.env['locomotive.path'] || request.path_info

        redirections_hash.each do |source, target|
          next unless (values = dynamic_values(source, path)) && (location = target_location(target, values))

          return location
        end

        false
      end

      def dynamic_values(source, path)
        # A rule with a query is never dynamic.
        return if source.include?('?') || !source.match?(PARAM)

        parts = source.split(PARAM).each_slice(2).to_a
        names = parts.filter_map { |_, name| name }
        return if names.uniq.size < names.size || parts.drop(1).any? { |text, name| name && text.empty? }

        pattern = parts.map { |text, name| Regexp.escape(text) + (name ? '([^/]+)' : '') }.join
        (match = /\A#{pattern}\z/.match(path)) && names.zip(match.captures).to_h
      end

      # Captures cannot set the destination authority.
      def target_location(target, values)
        authority_prefix, path, query, fragment = target.match(TARGET_PARTS).captures
        # Decode path escapes once before encoding query substitutions.
        query_values = values.transform_values { |value| Rack::Utils.escape(Rack::Utils.unescape_path(value)) }
        location     = [authority_prefix, put_values(path, values), put_values(query.to_s, query_values), put_values(fragment, values)].join

        return unless location.match?(NO_SPACE_OR_CONTROL)

        location if authority_prefix || location == target || location.match?(WITHOUT_ORIGIN)
      end

      def put_values(text, values)
        text.gsub(PARAM) { values.fetch($1, $&) }
      end

    end
  end

end
