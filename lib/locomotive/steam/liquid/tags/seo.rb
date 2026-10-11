module Locomotive
  module Steam
    module Liquid
      module Tags
        module SEO

          class Base < ::Liquid::Tag

            def render(context)
              self.render_title(context) +
              self.render_metadata(context)
            end

            protected

            def render_title(context)
              title = self.value_for(:seo_title, context)
              title = context['site'].name.to_s if title.blank?

              %{
                <title>#{CGI.escapeHTML(title)}</title>
              }
            end

            def render_metadata(context)
              %{
                <meta name="description" content="#{CGI.escapeHTML(self.value_for(:meta_description, context))}">
                <meta name="keywords" content="#{CGI.escapeHTML(self.value_for(:meta_keywords, context))}">
              }
            end

            def value_for(attribute, context)
              object = self.metadata_object(context)
              value = object.try(attribute.to_sym).blank? ? context['site'].send(attribute.to_sym) : object.send(attribute.to_sym)
              value.to_s.strip
            end

            def metadata_object(context)
              context['content_entry'] || context['page']
            end
          end

          class Title < Base

            def render(context)
              self.render_title(context)
            end

          end

          class Metadata < Base

            def render(context)
              self.render_metadata(context)
            end

          end

        end

        ::Liquid::Environment.default.register_tag('seo'.freeze, SEO::Base)
        ::Liquid::Environment.default.register_tag('seo_title'.freeze, SEO::Title)
        ::Liquid::Environment.default.register_tag('seo_metadata'.freeze, SEO::Metadata)
      end
    end
  end
end
