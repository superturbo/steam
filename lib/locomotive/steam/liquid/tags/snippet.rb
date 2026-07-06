module Locomotive
  module Steam
    module Liquid
      module Tags

        class Snippet < ::Liquid::Include

          def parse(tokens)
            # look for editable elements (only used by the Engine)
            # In the next version of Locomotive (v5), we won't support the editable elements
            # NOTE: it doesn't support dynamically choosen template
            template_name = template_name_expr.respond_to?(:name) ? template_name_expr.name : template_name_expr

            # make sure we keep track of the parsed snippets
            parse_context[:parsed_snippets] ||= []

            # already parsed? (it happens when doing recursivity with snippets)
            if parse_context[:parsed_snippets].include?(template_name)
              return
            else
              parse_context[:parsed_snippets] << template_name
            end

            ActiveSupport::Notifications.instrument('steam.parse.include', page: parse_context[:page], name: template_name)

            if parse_context[:snippet_finder] && snippet = parse_context[:snippet_finder].find(template_name)
              parse_context[:parser]._parse(snippet, parse_context.merge(snippet: template_name))
            end
          end

          def render_to_output_buffer(context, output)
            # parse_context (previously @options) doesn't include the page key if cache is on
            parse_context[:page] = context.registers[:page]

            begin
              super
            rescue ::Liquid::ArgumentError
              # NOTE: Locomotive site developers should always use quotes (or doubles quotes) for the name of a snippet.
              # Unfortunately, a lot of sites don't use them. So here is a little patch to not break those sites.
              Locomotive::Common::Logger.warn("Use quotes if the name of your snippet (#{template_name_expr.name}) is not dynamic.")

              @template_name_expr = template_name_expr.name

              super
            end
          end

        end

        ::Liquid::Template.register_tag('include'.freeze, Snippet)
      end
    end
  end
end
