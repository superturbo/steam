require 'rack/csrf'

module Locomotive
  module Steam

    class CsrfProtectionService

      attr_accessor_initialize :enabled, :field, :env

      def enabled?
        !!enabled
      end

      def token
        Rack::Csrf.token(env) if enabled?
      end

      def verified?(submitted)
        return true unless enabled?

        expected = env['rack.session']&.[](Rack::Csrf.key)

        [expected, submitted].all? { |token| token.is_a?(String) && !token.empty? } &&
          Rack::Utils.secure_compare(expected, submitted)
      end

    end

  end
end
