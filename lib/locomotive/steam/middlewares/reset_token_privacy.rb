module Locomotive::Steam
  module Middlewares

    # A password reset link carries its token in the query string: keep the
    # responses Steam returns to it, redirects included, out of caches and referrers.
    class ResetTokenPrivacy

      TOKEN_PARAM = 'auth_reset_token'

      def initialize(app)
        @app = app
      end

      def call(env)
        return @app.call(env) unless reset_token?(env['QUERY_STRING'].to_s)

        env['steam.no_store'] = true

        status, headers, body = @app.call(env)
        headers['cache-control']   = 'no-store'
        headers['referrer-policy'] = 'no-referrer'
        [status, headers, body]
      end

      private

      # Each pair is parsed on its own, as Rack names it, so a malformed one does not hide the token.
      def reset_token?(query)
        query.split(Rack::QueryParser::DEFAULT_SEP).any? do |pair|
          Rack::Utils.parse_nested_query(pair).key?(TOKEN_PARAM)
        rescue Rack::BadRequest
          false
        end
      end

    end

  end
end
