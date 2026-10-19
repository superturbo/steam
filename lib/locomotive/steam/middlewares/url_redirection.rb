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
        source, location = matching_rule
        return unless location

        emit_event(source)
        redirect_to location
      end

      protected

      def requested_path
        request.env['locomotive.path'] || request.path_info
      end

      def requested_path_with_query
        request.query_string.empty? ? requested_path : "#{requested_path}?#{request.query_string}"
      end

      def emit_event(source)
        ActiveSupport::Notifications.instrument('steam.serve.url_redirection', {
          site_id:  site._id,
          source:   source,
          url:      requested_path
        })
      end

      def matching_rule
        return if site.url_redirections.nil? || site.url_redirections.size == 0

        rules = site.url_redirections.to_h
        [requested_path_with_query, requested_path].uniq.each { |source| return [source, rules[source]] if rules[source] }

        find_dynamic_url_redirection(rules)
      end

      def find_dynamic_url_redirection(rules)
        rules.each do |source, target|
          next unless (values = dynamic_values(source, requested_path)) && (location = target_location(target, values))

          return [source, location]
        end

        nil
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
