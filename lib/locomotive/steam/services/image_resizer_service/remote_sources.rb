module Locomotive
  module Steam
    class ImageResizerService

      # The URL prefix the host lets resize jobs fetch from. It checks a URL before Steam signs it, and
      # matches as a Dragonfly fetch_url whitelist pattern when a job runs. Only the initial URL is checked;
      # Dragonfly does not recheck redirects.
      class RemoteSources

        # An http or https URL prefix naming a host, without a user, a query or a fragment.
        def self.prefix?(prefix)
          return false unless prefix.is_a?(String)

          uri = URI.parse(prefix)
          uri.is_a?(URI::HTTP) && uri.hostname.present? && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?
        rescue URI::InvalidURIError
          false
        end

        def ===(url)
          check(url)
          true
        rescue ::Dragonfly::Job::Fetch::NotFound
          false
        end

        def check(url)
          uri = parse(url)
          refuse(uri, 'is not from a trusted resize source') unless trusted?(uri)
          uri
        end

        private

        def parse(url)
          uri = URI.parse(url.to_s)

          refuse(nil, 'is not an http or https URL') unless uri.is_a?(URI::HTTP) && uri.hostname.present?
          refuse(uri, 'names a user') if uri.userinfo
          refuse(uri, 'holds a dot segment or an encoded separator') unless plain_path?(uri.path)

          uri
        rescue URI::InvalidURIError
          refuse(nil, 'is not a valid URL')
        end

        def plain_path?(path)
          path.exclude?('\\') && path !~ /%(2e|2f|5c)/i && path.split('/').none? { |segment| %w(. ..).include?(segment) }
        end

        def trusted?(uri)
          prefix = Locomotive::Steam.configuration.image_resizer_remote_source_prefix

          # A value that is not a prefix trusts nothing, even when it was set after start.
          return false unless self.class.prefix?(prefix)

          source = URI.parse(prefix)
          path   = source.path.end_with?('/') ? source.path : "#{source.path}/"

          source.scheme == uri.scheme && source.hostname.casecmp?(uri.hostname) && source.port == uri.port &&
            uri.path.start_with?(path)
        end

        # Names the scheme, host and path only: a user, a password or a query may hold a secret.
        def refuse(uri, reason)
          source = " #{"#{uri.scheme}://#{uri.host}#{uri.path}".inspect}" if uri
          raise ::Dragonfly::Job::Fetch::NotFound, "the resize source#{source} #{reason}"
        end

      end

    end
  end
end
