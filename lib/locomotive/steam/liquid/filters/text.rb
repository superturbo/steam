module Locomotive
  module Steam
    module Liquid
      module Filters
        module Text

          def underscore(input)
            input.to_s.gsub(' ', '_').gsub('/', '_').underscore
          end

          def dasherize(input)
            input.to_s.gsub(' ', '-').gsub('/', '-').dasherize
          end

          def encode(input)
            Rack::Utils.escape(input)
          end

          def parameterize(input)
            input.parameterize
          end

          # alias newline_to_br
          def multi_line(input)
            input.to_s.gsub("\n", '<br/>')
          end

          def concat(input, *args)
            if input.is_a?(::Array)
              # Liquid's built-in array concat semantics
              array = args.first
              raise ::Liquid::ArgumentError, 'concat filter requires an array argument' unless array.respond_to?(:to_ary)
              ::Liquid::StandardFilters::InputIterator.new(input, @context).concat(array)
            else
              result = input.to_s
              args.flatten.each { |a| result << a.to_s }
              result
            end
          end

          # right justify and padd a string
          def rjust(input, integer, padstr = '')
            input.to_s.rjust(integer, padstr)
          end

          # left justify and padd a string
          def ljust(input, integer, padstr = '')
            input.to_s.ljust(integer, padstr)
          end

          def textile(input)
            @context.registers[:services].textile.to_html(input)
          end

          def markdown(input)
            @context.registers[:services].markdown.to_html(input)
          end

        end

        ::Liquid::Template.register_filter(Text)

      end
    end
  end
end
