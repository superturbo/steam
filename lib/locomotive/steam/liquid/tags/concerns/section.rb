module Locomotive::Steam::Liquid::Tags::Concerns

  module Section

    private

    def render_section(context, template, section, content)
      context.stack do
        # build a drop from the content and add it to the new context
        context['section'] = Locomotive::Steam::Liquid::Drops::Section.new(
          section,
          content
        )

        # assign an id if specified in the context
        context['section'].id = context['section_id'] if context['section_id'].present?

        begin
          _render(context, template)
        rescue Locomotive::Steam::TemplateError => e
          e.template_name = "sections--#{section.name}"
          raise e
        end
      end
    end

    def _render(context, template)
      if context.registers[:live_editing]
        editor_settings_lookup(template.root)
      end

      html = template.render(context)

      # by default, Steam will wrap the section HTML to make sure it has all the
      # DOM attributes the live editing editor needs.
      if context['is_section_locomotive_attributes_displayed']
        html
      else
        wrap_html(html, context)
      end
    end

    def wrap_html(html, context)
      section     = context['section']
      css_class   = context['section_css_class']

      # we need the section_css_class once
      # context.scopes.last.delete('section_css_class')

      anchor_id = %(id="#{section.anchor_id}")
      tag_id    = %(id="locomotive-section-#{section.id}")
      tag_class = %(class="#{['locomotive-section', section.css_class, css_class].compact.join(' ')}")
      tag_data  = %(data-locomotive-section-type="#{section.type}")

      %(<div #{tag_id} #{tag_class} #{tag_data}><span #{anchor_id}></span>#{html}</div>)
    end

    # in order to enable string/text synchronization with the editor:
    # - find variables like {{ section.settings.<id> }} or {{ block.settings.<id> }}
    # - once found, get the closest tag
    # - add custom data attributes to it
    #
    # Liquid 5 freezes parsed bodies, so rebuild and reattach changed bodies.
    def editor_settings_lookup(root)
      transform_node(root)
    end

    def transform_node(node)
      node.instance_variables.each do |ivar|
        value = node.instance_variable_get(ivar)

        case value
        when ::Liquid::BlockBody
          transformed = transform_body(value)
          node.instance_variable_set(ivar, transformed) unless transformed.equal?(value)
        when Array
          # if/case tags hold their bodies through condition attachments
          value.each { |item| transform_attachment(item) }
        end
      end
    end

    def transform_attachment(condition)
      return unless condition.respond_to?(:attachment) && condition.attachment.is_a?(::Liquid::BlockBody)

      transformed = transform_body(condition.attachment)
      condition.instance_variable_set(:@attachment, transformed) unless transformed.equal?(condition.attachment)
    end

    def transform_body(body)
      nodelist = body.nodelist
      return body if nodelist.blank?

      previous_node = nil
      new_nodelist  = []
      changed       = false

      nodelist.each_with_index do |node, index|
        if node.is_a?(::Liquid::Variable) && previous_node.is_a?(String)
          matches = node.raw.match(Locomotive::Steam::SECTIONS_SETTINGS_VARIABLE_REGEXP)

          # is a section setting variable?
          if matches && matches[:id] && wrapped_around_tag?(index, nodelist)
            # open the closest HTML tag
            previous_node.gsub!(/>(\s*)\z/, '\1')

            # here we go, add a liquid variable!
            new_nodelist.push(::Liquid::Variable.new(
              "section.editor_setting_data.#{matches[:id]}",
              node.parse_context)
            )

            # close the tag
            new_nodelist.push('>')

            changed = true
          end
        elsif !node.is_a?(String)
          transform_node(node)
        end

        new_nodelist.push(node)

        previous_node = node
      end

      return body unless changed

      body.dup.tap { |copy| copy.instance_variable_set(:@nodelist, new_nodelist) }
    end

    def wrapped_around_tag?(index, nodelist)
      return false if index + 1 >= nodelist.size

      previous_node = nodelist[index - 1]
      next_node     = nodelist[index + 1]

      return false unless next_node.is_a?(String)

      (previous_node =~ /\>\s*\z/).present? && (next_node =~ /\A\s*\</).present?
    end

    def notify_on_parsing(type, source: :page, is_dropzone: false, key: nil, id: nil, label: nil, placement: nil)
      ActiveSupport::Notifications.instrument('steam.parse.section', {
        attributes: {
          type:         type,
          source:       source,
          id:           id,
          key:          key,
          is_dropzone:  is_dropzone,
          label:        label,
          placement:    placement
        },
        page:   options[:page],
        block:  current_inherited_block_name
      })
    end

    def current_inherited_block_name
      options[:inherited_blocks].try(:[], :nested).try(:last).try(:name)
    end

  end

end
