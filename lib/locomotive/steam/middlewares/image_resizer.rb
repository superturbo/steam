module Locomotive::Steam
  module Middlewares

    class ImageResizer

      attr_accessor_initialize :app

      def call(env)
        status, headers, body = resize(env)
        return app.call(env) if headers.transform_keys(&:downcase)['x-cascade'] == 'pass'

        headers = headers.merge('cache-control' => 'no-store') if status >= 400
        [status, headers, body]
      end

      private

      def resize(env)
        ImageResizerService::Shell.with_site(job_site(env)) { ::Dragonfly.app(:steam).call(env) }
      rescue ImageResizerService::CommandSlots::Busy
        busy(env)
      rescue ImageResizerService::CommandSlots::Unavailable => e
        Locomotive::Common::Logger.error e.message
        refusal(env, 'Unavailable')
      end

      # The rendering site a job names; Dragonfly runs no command for a job Steam did not sign.
      def job_site(env)
        resizer = ::Dragonfly.app(:steam)
        params  = ::Dragonfly::UrlMapper.new(resizer.server.url_format).params_for(env['PATH_INFO'], env['QUERY_STRING'])
        return unless params && params['job']

        thumb = ::Dragonfly::Job.deserialize(params['job'], resizer).steps.grep(::Dragonfly::Job::Process)
                                .map(&:args).find { |name, *| name.to_s == 'thumb' }
        thumb.last['site'] if thumb&.last.is_a?(Hash)
      rescue ::Dragonfly::Serializer::BadString, ::Dragonfly::Serializer::MaliciousString, ::Dragonfly::Job::InvalidArray
        nil
      end

      def busy(env)
        wait = Locomotive::Steam.configuration.image_magick_command_queue_timeout
        refusal(env, 'Busy', 'retry-after' => [wait.ceil, 1].max.to_s)
      end

      def refusal(env, text, headers = {})
        [503, { 'content-type' => 'text/plain' }.merge(headers), env['REQUEST_METHOD'] == 'HEAD' ? [] : [text]]
      end

    end

  end
end
