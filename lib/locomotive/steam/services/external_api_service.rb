require 'uri'
require 'httparty'

module Locomotive
  module Steam
    class ExternalAPIService

      include ::HTTParty

      # Timeouts limit individual waits, not the whole call. Disable retries to
      # avoid holding the request thread for a second attempt.
      open_timeout 3
      read_timeout 3
      default_options[:max_retries] = 0

      def initialize(log_rules = [])
        @log_rules = Array(log_rules)
      end

      # Available option keys:
      # - method
      # - data
      # - format
      # - username / password (basic auth)
      # - headers
      # - header_auth
      # - with_user_agent
      #
      def consume(url, options = {}, with_status = false)
        base_uri, path = extract_base_uri_and_path(url)

        method = (options[:method] || 'GET').to_s.downcase

        _options = build_httpparty_options(options, method)
        _options[:base_uri] = base_uri

        if with_status
          verbose_perform_request_to(method, path, _options)
        else
          perform_request_to(method, path, _options)
        end
      end

      private

      def build_httpparty_options(options, method)
        _options = {}

        # data: body (POST/PUT/PATCH) or query (GET)
        _options[method == 'get' ? :query : :body] = options[:data] if options[:data]

        # basic auth?
        username, password = options[:username], options[:password]
        _options[:basic_auth] = { username: username, password: password } if username

        # headers
        _options[:headers] = (options[:headers] || {}).dup
        _options[:headers]['Authorization'] = options[:header_auth] if options[:header_auth]
        _options[:headers]['User-Agent'] = 'LocomotiveCMS' if options[:with_user_agent]
        _options.delete(:headers) if _options[:headers].blank?

        # format
        if options.has_key?(:format) && options[:format] != 'default'
          _options[:format] = options[:format].gsub(/[\'\"]/, '').to_sym
        end

        _options
      end

      def extract_base_uri_and_path(url)
        url = HTTParty.normalize_base_uri(url)

        uri       = URI.parse(url)
        path      = uri.request_uri || '/'
        base_uri  = "#{uri.scheme}://#{uri.host}"
        base_uri  += ":#{uri.port}" if (uri.port != 80 && uri.port != 443)

        [base_uri, path]
      end

      def perform_request_to(method, path, options)
        response = self.class.send(method.to_sym, path, options)
        call     = "[WebService] #{method.to_s.upcase} #{LogFilter.url("#{options[:base_uri]}#{path}", @log_rules)}"

        if response.code == 200
          HashConverter.to_underscore(parsed_response(response, call))
        else
          failed(call, "failed with status #{response.code}") { debug_response_body(response) }
        end
      end

      def parsed_response(response, call)
        response.parsed_response
      rescue StandardError => error
        failed(call, "answered 200 with a body that cannot be read as #{response.request.format} (#{error.class})") { debug_text(response.body) }
      end

      def failed(call, outcome)
        Locomotive::Common::Logger.error "#{call} #{outcome}"
        Locomotive::Common::Logger.debug "#{call} response: #{yield}" if Locomotive::Common::Logger.instance.logger&.debug?
        nil
      end

      def debug_response_body(response)
        parsed_response = begin
          response.parsed_response
        rescue StandardError
          nil
        end

        debug_text(parsed_response.is_a?(Hash) ? LogFilter.params(parsed_response, @log_rules).inspect : response.body)
      end

      def debug_text(text)
        text.to_s.truncate(1_000)
      end

      def verbose_perform_request_to(method, path, options)
        response        = self.class.send(method.to_sym, path, options)
        parsed_response = response.parsed_response
        {
          status: response.code,
          data:   HashConverter.to_underscore(parsed_response)
        }
      rescue Exception => e
        { status: nil, error: e.message }
      end

    end
  end
end
