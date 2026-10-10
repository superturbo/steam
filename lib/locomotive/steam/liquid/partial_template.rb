module Locomotive
  module Steam
    module Liquid

      class PartialTemplate < ::Liquid::Template

        def parse(source, options = {})
          super
        rescue ::Liquid::SyntaxError => e
          raise Locomotive::Steam::LiquidError.new(e, name, source)
        end

      end

      class PartialTemplateFactory

        def for(template_name)
          PartialTemplate.new.tap { |template| template.name = template_name }
        end

      end

    end
  end
end
