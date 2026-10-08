module Locomotive::Steam
  module Middlewares

    class ImageResizer

      attr_accessor_initialize :app

      def call(env)
        status, headers, body = ::Dragonfly.app(:steam).call(env)
        return app.call(env) if headers.transform_keys(&:downcase)['x-cascade'] == 'pass'

        headers = headers.merge('cache-control' => 'no-store') if status >= 400
        [status, headers, body]
      end

    end

  end
end
