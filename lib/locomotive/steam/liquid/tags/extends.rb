module Locomotive
  module Steam
    module Liquid
      module Tags

        # Extends allows designer to use template inheritance.
        #
        #   {% extends home %}
        #   {% block content }Hello world{% endblock %}
        #
        class Extends < ::Liquid::Block
          SYNTAX = /(#{::Liquid::QuotedFragment}+)/o

          def initialize(tag_name, markup, options)
            super

            if markup =~ SYNTAX
              @template_name = Regexp.last_match(1).gsub(/["']/o, '').strip
            else
              raise ::Liquid::SyntaxError.new("Syntax Error in 'extends' - Valid syntax: extends <page_handle_or_parent_keyword>")
            end

            # variables needed by the inheritance mechanism during the parsing
            options[:inherited_blocks] ||= {
              nested: [], # used to get the full name of the blocks if nested (stack mechanism)
              all: {}, # keep track of the blocks by their full name
            }
          end

          def parse(tokens)
            super

            parent_template = parse_parent_template

            # replace the nodes of the current template by those from the parent
            # which itself may have have done the same operation if it includes
            # the extends tag.
            # Liquid 5 freezes parsed bodies, so replace the body instead of its nodelist.
            body = @body.frozen? ? @body.dup : @body
            body.instance_variable_set(:@nodelist, parent_template.root.nodelist.dup)
            @body = body
          end

          def blank?
            false
          end

          def render(context)
            context.stack do
              context['layout_name'] = @layout_name
              super
            end
          end

          protected

          def parse_body(body, tokens)
            body.parse(tokens, options) do |end_tag_name, _|
              @blank &&= body.blank?

              # Note: extends does not require the "end tag".
              return false if end_tag_name.nil?
            end

            true
          end

          def parse_parent_template
            parent = parse_context[:parent_finder].find(parse_context[:page], @template_name)

            raise Liquid::PageNotFound.new("Extending a missing page. Page/Layout with fullpath '#{@template_name}' was not found") if parent.nil?

            pages      = parse_context[:extended_pages] || [parse_context[:page]].compact
            loop_start = pages.index { |page| page._id == parent._id }
            raise_loop(pages[loop_start..] + [parent]) if loop_start

            ActiveSupport::Notifications.instrument('steam.parse.extends', page: parse_context[:page], parent: parent)

            @layout_name = parent.handle || parent.slug

            parse_context[:parser]._parse(parent, parse_context.merge(page: parent, extended_pages: pages + [parent]))
          end

          def raise_loop(pages)
            error = Liquid::CyclicExtends.new("Pages extend each other in a loop: #{pages.map(&:fullpath).join(', ')}")
            error.line_number = line_number
            raise error
          end
        end

        ::Liquid::Environment.default.register_tag('extends', Extends)
      end
    end
  end
end
