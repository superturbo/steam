module Locomotive::Steam
  module Middlewares

    # Track the request into the current logger
    #
    class Logging

      include Concerns::Helpers

      attr_accessor_initialize :app

      def call(env)
        started_at    = Time.now
        monotonic_from = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        log "Started #{env['REQUEST_METHOD'].upcase} \"#{env['PATH_INFO']}\" at #{started_at}".light_white, 0

        debug_log "Params: #{env.fetch('steam.request').params.inspect}"

        response = begin
          app.call(env)
        rescue StandardError => exception
          errored_in_ms = elapsed_ms(monotonic_from)

          # error level (not the info-level `log` helper) so it survives a
          # production :warn log level
          Locomotive::Common::Logger.error "  " +
            "Errored with #{exception.class.name} in #{errored_in_ms}ms: #{exception.message}\n\n".red

          ActiveSupport::Notifications.instrument('steam.render.error', {
            site_id:          env['steam.site']&._id,
            site_handle:      env['steam.site']&.handle,
            domain:           env['SERVER_NAME'],
            method:           env['REQUEST_METHOD'],
            locale:           env['steam.locale'].to_s,
            path:             env['PATH_INFO'],
            time_in_ms:       errored_in_ms,
            exception_class:  exception.class.name,
            exception:        [exception.class.name, exception.message],
            exception_object: exception
          })
          raise
        end

        done_in_ms = elapsed_ms(monotonic_from)
        log "Completed #{code_to_human(response.first)} in #{done_in_ms}ms\n\n".green

        ActiveSupport::Notifications.instrument('steam.http.render', {
          site_id:     env['steam.site']&._id,
          site_handle: env['steam.site']&.handle,
          domain:      env['SERVER_NAME'],
          method:      env['REQUEST_METHOD'],
          locale:      env['steam.locale'].to_s,
          path:        env['PATH_INFO'],
          status:      response.first,
          time_in_ms:  done_in_ms
        })

        response
      end

      protected

      # Elapsed time in milliseconds (0.1ms precision), measured with a
      # monotonic clock so NTP adjustments can never produce a negative or
      # inflated duration in the latency metrics.
      def elapsed_ms(monotonic_from)
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - monotonic_from) * 10000).truncate / 10.0
      end

      def code_to_human(code)
        status = code.to_i
        "#{status} #{Rack::Utils::HTTP_STATUS_CODES[status]}".strip
      end

    end
  end
end
