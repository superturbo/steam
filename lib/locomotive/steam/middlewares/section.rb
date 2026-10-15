require 'json'

module Locomotive::Steam
  module Middlewares
    class Section < ThreadSafe

      include Concerns::Helpers
      include Concerns::LiquidContext
      include Liquid::Tags::Concerns::Section

      def _call
        return unless env['steam.live_editing'] && (section_type = get_section_type)

        if (section = services.section_finder.find(section_type))
          render_response(render(section, section_type), 200)
        else
          render_response('Section not found', 404, 'text/plain')
        end
      end

      private

      def get_section_type
        request.get_header('HTTP_LOCOMOTIVE_SECTION_TYPE')
      end

      # Parse the stored section template, never the header value.
      def render(section, section_type)
        context  = liquid_context
        template = parse_template(section, section_type)

        if (content = section_content)
          context['section_id'] = content['id'] || section_type
        else
          context['section_id'] = "page-#{section_type}"
          content = context['page']&.sections_content&.fetch(section_type, nil)
        end

        render_section(context, template, section, content)
      end

      # Preserve the section template name in syntax errors.
      def parse_template(section, section_type)
        Liquid::Template.parse(section.liquid_source)
      rescue ::Liquid::SyntaxError => error
        raise LiquidError.new(error, "sections--#{section_type}", section.liquid_source)
      end

      def section_content
        return {} unless (data = json_body)

        content = data['section_content']
        return content if content.nil? || content.is_a?(Hash)

        raise InvalidJsonBody, 'The section content is not a JSON object.'
      end

      def live_editing?
        true
      end

    end
  end
end
