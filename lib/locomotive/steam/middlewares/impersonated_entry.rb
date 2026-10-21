module Locomotive::Steam
  module Middlewares

    # Displays the impersonation banner and handles posted stop requests.
    class ImpersonatedEntry < ThreadSafe

      include Concerns::Helpers
      include Concerns::AuthHelpers
      include Concerns::CsrfProtection

      def _call
        if stopping?
          return refuse_unverified_form unless form_token_verified?

          services.auth.notify(:signed_out, request.env['steam.authenticated_entry'], request)
          store_authenticated(nil)
          redirect_to_local_path(local_request_path, 303)
        elsif authenticated? && is_impersonating?
          env['steam.impersonating_authenticated_entry'] = true
          liquid_assigns["is_impersonating_current_#{authenticated_entry_type.singularize}"] = true
        end
      end

      def next
        response = super
        status, headers, body = response

        if authenticated? && is_impersonating? && html? && headers['content-type'].to_s.start_with?(HTML_CONTENT_TYPE)
          html = body.first.gsub(/<body[^>]*>/) do |opening_body|
            opening_body + banner_html(env['steam.authenticated_entry'])
          end

          [status, headers, [html]]
        else
          response
        end
      end

      private

      def stopping?
        originally_posted? && params[:impersonating] == 'stop' && authenticated? && is_impersonating? &&
          !env['steam.rendering_entry_errors']
      end

      def is_impersonating?
        request.session[:authenticated_impersonation] == '1'
      end

      def banner_html(entry)
        <<-HTML
<div
  class="locomotive-impersonating-banner"
  style="position: fixed; bottom: 0; left: 0; z-index: 9999; width: 100%;background: #61D5AB; text-align: center; color: #fff; padding: 1rem 0rem;"
>
  You're impersonating <b>#{CGI.escapeHTML(entry._label.to_s)}</b>.
  <form method="post" action="#{CGI.escapeHTML(stop_form_path)}" style="display: inline; margin: 0">
    <input type="hidden" name="impersonating" value="stop">#{form_token_html}
    <button type="submit" style="background: none; border: 0; padding: 0; color: #fff; font: inherit; text-decoration: underline; cursor: pointer">
      Stop impersonating
    </button>
  </form>
</div>
        HTML
      end

      def stop_form_path
        local_path?(request.path) ? request.path : '/'
      end

      def form_token_html
        csrf = services.csrf_protection
        return '' unless csrf.enabled?

        %(<input type="hidden" name="#{CGI.escapeHTML(csrf.field)}" value="#{CGI.escapeHTML(csrf.token)}">)
      end

    end

  end
end
