module Locomotive
  module Steam
    module Liquid
      module Filters
        module Base

          def absolute_url(url)
            url =~ Locomotive::Steam::IsHTTP ? url : URI.join(@context['base_url'], url).to_s
          end

          protected

          # Convert an array of properties ('key:value') into a hash
          # Ex: ['width:50', 'height:100'] => { width: '50', height: '100' }
          def args_to_options(*args)
            options = {}
            args.flatten.each do |a|
              next unless HtmlEscapedText.original(a) =~ /^([^:\n]*):(.*)$/

              name, value = $1, $2
              options[name.to_sym] = HtmlEscapedText.map(a) { value }
            end
            options
          end

          def inline_options(options = {})
            return '' if options.empty?
            (options.stringify_keys.sort.to_a.collect { |a, b| "#{a}=\"#{HtmlEscapedText.escape(b)}\"" }).join(' ') << ' '
          end

          # Get the url to be used in html tags such as image_tag, flash_tag, ...etc
          # input: url (String) OR asset drop
          def get_url_from_asset(input)
            input.respond_to?(:url) ? input.url : input
          end

          def any_asset_url(input, extension = nil, folder = nil)
            return '' if input.nil?

            if input =~ /^https?:/
              input
            else
              uri = input.starts_with?('/') ? URI(input) : URI(asset_url(folder.blank? ? input : "#{folder}/#{input}"))
              uri.path = "#{uri.path}#{extension}" unless extension.blank? || uri.path.ends_with?(extension)
              uri.to_s
            end
          end

          def asset_url(path)
            @context.registers[:services].theme_asset_url.build(path)
          end

        end

        ::Liquid::Environment.default.register_filter(Base)

      end
    end
  end
end
