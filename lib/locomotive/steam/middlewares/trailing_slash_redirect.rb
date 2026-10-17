module Locomotive::Steam
  module Middlewares

    # Preserve rack-rewrite's query-string matching semantics.
    class TrailingSlashRedirect

      def initialize(app)
        @app = app
      end

      def call(env)
        query   = env['QUERY_STRING'].to_s
        subject = env['PATH_INFO'].to_s
        subject = "#{subject}?#{query}" unless query.empty?

        match    = %r{^/(.*)/$}.match(subject)
        location = "/#{match[1]}" if match

        if location&.match?(Locomotive::Steam::IsLocalPath)
          [301, { 'location' => location, 'content-length' => '0' }, []]
        else
          @app.call(env)
        end
      end

    end

  end
end
