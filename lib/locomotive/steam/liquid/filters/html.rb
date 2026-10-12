require 'cgi'

module Locomotive
  module Steam
    module Liquid
      module Filters
        module Html

          SAFE_URL_SCHEMES = %w[http https mailto tel].freeze
          private_constant :SAFE_URL_SCHEMES

          # Validate and HTML-escape a CMS URL for quoted a[href]/img[src] attributes.
          # Rejects non-allowlisted schemes and ASCII control chars; not for script/iframe/form/CSS/JS.
          # Output is attribute-safe — do NOT chain an extra `| escape`.
          def safe_url(input)
            url = HtmlEscapedText.original(input).to_s
            return '' if url.match?(/[\x00-\x1F\x7F]/)

            url = url.strip
            scheme = url[/\A([a-z][a-z0-9+.-]*):/i, 1]

            return '' if scheme && !SAFE_URL_SCHEMES.include?(scheme.downcase)

            HtmlEscapedText.new(url)
          end

          # Return a link tag that browsers and news readers can use to auto-detect an RSS or ATOM feed.
          # input: url of the feed
          # example:
          #   {{ '/foo/bar' | auto_discovery_link_tag: 'rel:alternate', 'type:application/atom+xml', 'title:A title' }}
          def auto_discovery_link_tag(input, *args)
            options = args_to_options(args)

            rel   = options[:rel] || 'alternate'
            type  = options[:type] || 'application/rss+xml'
            title = options[:title] || 'RSS'

            %{<link rel="#{HtmlEscapedText.escape(rel)}" type="#{HtmlEscapedText.escape(type)}" title="#{HtmlEscapedText.escape(title)}" href="#{HtmlEscapedText.escape(input)}" />}
          end

          # Write the url of any theme file
          def theme_asset_url(input)
            HtmlEscapedText.map(input) { |text| any_asset_url(text) }
          end

          # Write the url of a theme stylesheet
          # input: name of the css file
          def stylesheet_url(input)
            HtmlEscapedText.map(input) { |text| any_asset_url(text, '.css', 'stylesheets') }
          end

          # Write the link tag of a theme stylesheet
          # input: url of the css file
          def stylesheet_tag(input, media = 'screen')
            return '' if input.nil?

            input = stylesheet_url(input)

            %{<link href="#{HtmlEscapedText.escape(input)}" media="#{HtmlEscapedText.escape(media)}" rel="stylesheet" type="text/css" />}
          end

          # Write the url to javascript resource
          # input: name of the javascript file
          def javascript_url(input)
            HtmlEscapedText.map(input) { |text| any_asset_url(text, '.js', 'javascripts') }
          end

          # Write the link to javascript resource
          # input: url of the javascript file
          def javascript_tag(input, *args)
            return '' if input.nil?

            javascript_options = inline_options(args_to_options(args))
            input = javascript_url(input)

            %{<script src="#{HtmlEscapedText.escape(input)}" type="text/javascript" #{javascript_options}></script>}
          end

          def theme_image_url(input)
            return '' if input.nil?

            HtmlEscapedText.map(input) do |text|
              text = "images/#{text}" unless text.starts_with?('/')

              asset_url(text)
            end
          end

          # Write a theme image tag
          # input: name of file including folder
          def theme_image_tag(input, *args)
            image_options = inline_options(args_to_options(args))

            %{<img src="#{HtmlEscapedText.escape(theme_image_url(input))}" #{image_options}>}
          end

          # Write an image tag
          # input: url of the image OR asset drop
          def image_tag(input, *args)
            image_options = inline_options(args_to_options(args))

            %{<img src="#{HtmlEscapedText.escape(get_url_from_asset(input))}" #{image_options}>}
          end

          # Embed a flash movie into a page
          # input: url of the flash movie OR asset drop
          # width: width (in pixel or in %) of the embedded movie
          # height: height (in pixel or in %) of the embedded movie
          def flash_tag(input, *args)
            path = HtmlEscapedText.escape(get_url_from_asset(input))
            embed_options = inline_options(args_to_options(args))
            html = <<-EOF
<object #{embed_options}>
  <param name="movie" value="#{path}">
  <embed src="#{path}" #{embed_options}>
  </embed>
</object>
EOF
            html.gsub(/ >/, '>').strip
          end

        end

        ::Liquid::Environment.default.register_filter(Html)

      end
    end
  end
end
