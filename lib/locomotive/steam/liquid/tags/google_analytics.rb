module Locomotive
  module Steam
    module Liquid
      module Tags
        class GoogleAnalytics < ::Liquid::Tag

          Syntax = /(#{::Liquid::QuotedFragment}+)/o.freeze

          attr_reader :account_id

          def initialize(tag_name, markup, options)
            super

            if markup =~ Syntax
              @account_id = ::Liquid::Expression.parse($1)
            else
              raise ::Liquid::SyntaxError.new("Syntax Error in 'google_analytics' - Valid syntax: google_analytics <account_id>")
            end
          end

          def render(context)
            id = context.evaluate(account_id)
            return '' if id.blank?

            ga_snippet(id.to_s)
          end

          private

          def ga_snippet(account_id)
            %{
              <!-- Google tag (gtag.js) -->
              <script async src="https://www.googletagmanager.com/gtag/js?id=#{ERB::Util.url_encode(account_id)}"></script>
              <script>
                window.dataLayer = window.dataLayer || [];
                function gtag(){dataLayer.push(arguments);}
                gtag('js', new Date());

                gtag('config', #{ERB::Util.json_escape(account_id.to_json)});
              </script>
            }
          end

        end

        ::Liquid::Environment.default.register_tag('google_analytics'.freeze, GoogleAnalytics)

      end
    end
  end
end
