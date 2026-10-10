module Locomotive::Steam
  module Middlewares
    module Concerns
      # The token comes from a body field or the X-CSRF-Token header, never from the query string.
      module CsrfProtection

        UNVERIFIED_FORM = 'The form could not be verified. Reload the page and submit it again.'.freeze

        def form_token_verified?
          submitted_form_tokens.any? { |token| services.csrf_protection.verified?(token) }
        end

        def refuse_unverified_form
          Locomotive::Common::Logger.warn "[#{self.class.name.demodulize}] Refused a form without a valid token"

          if json_request? || json?
            render_response({ error: UNVERIFIED_FORM }.to_json, 422, 'application/json')
          else
            render_response(UNVERIFIED_FORM, 422, 'text/plain')
          end
        end

        private

        def submitted_form_tokens
          [body_params[services.csrf_protection.field], env[Rack::Csrf.rackified_header]]
        end

      end
    end
  end
end
