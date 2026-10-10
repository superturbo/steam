require 'spec_helper'

describe Locomotive::Steam::Liquid::Tags::Section do

  let(:request)       { instance_double('Request', env: {}) }
  let(:services)      { Locomotive::Steam::Services.build_instance(request) }
  let(:finder)        { services.section_finder }
  let(:source)        { 'Locomotive {% section header %}' }
  let(:live_editing)  { true }
  let(:content)       { {} }
  let(:file_system)   { Locomotive::Steam::Liquid::FileSystem.new(section_finder: finder) }
  let(:page)          { liquid_instance_double('Page', sections_content: content)}
  let(:assigns)       { { 'page' => page } }
  let(:factory)       { Locomotive::Steam::Liquid::PartialTemplateFactory.new }
  let(:registers)     { { services: services, live_editing: live_editing, file_system: file_system, template_factory: factory } }
  let(:context)       { ::Liquid::Context.new(assigns, {}, registers, rethrow_errors: true) }

  describe 'parsing' do

    subject { parse_template(source) }

    describe 'raises an error if the syntax is incorrect' do
      let(:source) { 'Locomotive {% section %}' }
      it { expect { subject }.to raise_exception(Liquid::SyntaxError) }
    end

  end

  describe 'rendering' do

    before do
      allow(finder).to receive(:find).and_return(section)
    end

    subject { render_template(source, context) }

    let(:definition) { {
      type:  'header',
      class: 'my-awesome-header',
      settings: [
        { id: 'brand', type: 'text', label: 'Brand' },
        { id: 'image', type: 'image_picker' }
      ],
      blocks: [
        { type: 'menu_item', settings: [
          { id: 'title', type: 'text' },
          { id: 'image', type: 'image_picker' }
        ]}
      ],
      default: {
        settings: { brand: 'NoCoffee', image: 'foo.png' },
        blocks: [{ id: 42, type: 'menu_item', settings: { title: 'Home', image: 'foo.png' } }] }
    }.deep_stringify_keys }

    let(:section) { instance_double(
      'Header',
      slug:           'header',
      type:           'header',
      liquid_source:  liquid_source,
      definition:     definition,
    )}

    context 'no block' do

      let(:liquid_source) { %(built by <a>\n\t<strong>{{ section.settings.brand }}</strong></a>) }

      it { is_expected.to eq 'Locomotive'\
        ' <div id="locomotive-section-page-header"'\
        ' class="locomotive-section my-awesome-header"'\
        ' data-locomotive-section-type="header">'\
          '<span id="page-header-section"></span>'\
          'built by <a>' + %(\n\t) + '<strong data-locomotive-editor-setting="section-page-header.brand">NoCoffee</strong></a>'\
        '</div>' }

      context 'capturing the setting in a liquid variable' do

        let(:liquid_source) { %({% capture brand %}<strong class="bold">{{ section.settings.brand }}</strong>{% endcapture %}built by <a>\n\t{{ brand }}</a>) }

        it { is_expected.to eq 'Locomotive'\
          ' <div id="locomotive-section-page-header"'\
          ' class="locomotive-section my-awesome-header"'\
          ' data-locomotive-section-type="header">'\
            '<span id="page-header-section"></span>'\
            'built by <a>' + %(\n\t) + '<strong class="bold" data-locomotive-editor-setting="section-page-header.brand">NoCoffee</strong></a>'\
          '</div>' }

      end

      {
        '{{ section.settings.brand | upcase }}'           => 'NOCOFFEE',
        '{{section.settings.brand|upcase}}'               => 'NOCOFFEE',
        "{{ section.settings.brand | default: 'Brand' }}" => 'NoCoffee',
        '{{ section.settings.brand | strip }}'            => 'NoCoffee'
      }.each do |markup, value|
        context "filtering the setting with #{markup}" do

          let(:liquid_source) { "built by <a>\n\t<strong>#{markup}</strong></a>" }

          it { is_expected.to eq 'Locomotive'\
            ' <div id="locomotive-section-page-header"'\
            ' class="locomotive-section my-awesome-header"'\
            ' data-locomotive-section-type="header">'\
              '<span id="page-header-section"></span>'\
              'built by <a>' + %(\n\t) + %(<strong data-locomotive-editor-setting-render="section-page-header.brand">#{value}</strong></a>)\
            '</div>' }

        end
      end

      context 'filtering a non text type input' do

        let(:liquid_source) { "built by <strong>{{ section.settings.image | default: 'none' }}</strong>" }

        it { is_expected.to eq 'Locomotive'\
          ' <div id="locomotive-section-page-header"'\
          ' class="locomotive-section my-awesome-header"'\
          ' data-locomotive-section-type="header">'\
            '<span id="page-header-section"></span>'\
            'built by <strong>foo.png</strong>'\
          '</div>' }

      end

      context 'with a non string type input' do

        let(:liquid_source) { 'built by <strong>{{ section.settings.image }}</strong>' }

        it { is_expected.to eq 'Locomotive'\
          ' <div id="locomotive-section-page-header"'\
          ' class="locomotive-section my-awesome-header"'\
          ' data-locomotive-section-type="header">'\
            '<span id="page-header-section"></span>'\
            'built by <strong>foo.png</strong>'\
          '</div>' }

      end

      context 'including the link_to liquid tag' do

        let(:liquid_source) { 'go to {% link_to home %}' }

        before { expect_any_instance_of(Locomotive::Steam::Liquid::Tags::LinkTo).to receive(:render) { 'HOME' } }

        it { is_expected.to eq 'Locomotive'\
          ' <div id="locomotive-section-page-header"'\
          ' class="locomotive-section my-awesome-header"'\
          ' data-locomotive-section-type="header">'\
            '<span id="page-header-section"></span>'\
            'go to HOME'\
          '</div>' }

      end

      context 'without the live editing feature enabled' do

        let(:live_editing) { false }

        it { is_expected.to eq 'Locomotive '\
          '<div id="locomotive-section-page-header"'\
          ' class="locomotive-section my-awesome-header"'\
          ' data-locomotive-section-type="header">'\
            '<span id="page-header-section"></span>'\
            'built by <a>' + %(\n\t) + '<strong>NoCoffee</strong></a>'\
          '</div>' }

      end

      context 'the developer wants to wrap herself/himself the section' do

        let(:liquid_source) { '<section class="section-header" id="{{ section.anchor_id }}" {{ section.locomotive_attributes }}>Hello world</section>' }

        it { is_expected.to eq 'Locomotive '\
          '<section class="section-header"'\
          ' id="page-header-section"'\
          ' data-locomotive-section-id="page-header"'\
          ' data-locomotive-section-type="header">'\
            'Hello world'\
          '</section>' }

      end

    end

    context 'with blocks' do

      let(:liquid_source) { '{% for foo in section.blocks %}<a href="/">{{ foo.settings.title }}</a>{% endfor %}' }

      it { is_expected.to eq 'Locomotive'\
        ' <div id="locomotive-section-page-header"'\
        ' class="locomotive-section my-awesome-header"'\
        ' data-locomotive-section-type="header">'\
          '<span id="page-header-section"></span>'\
          '<a href="/" data-locomotive-editor-setting="section-page-header-block.42.title">Home</a>'\
        '</div>' }

      context 'filtering the setting' do

        let(:liquid_source) { '{% for foo in section.blocks %}<a href="/">{{ foo.settings.title | upcase }}</a>{% endfor %}' }

        it { is_expected.to eq 'Locomotive'\
          ' <div id="locomotive-section-page-header"'\
          ' class="locomotive-section my-awesome-header"'\
          ' data-locomotive-section-type="header">'\
            '<span id="page-header-section"></span>'\
            '<a href="/" data-locomotive-editor-setting-render="section-page-header-block.42.title">HOME</a>'\
          '</div>' }

      end

      context 'with a non text type input' do

        let(:liquid_source) { '{% for foo in section.blocks %}<a>{{ foo.settings.image }}</a>{% endfor %}' }

        it { is_expected.to eq 'Locomotive'\
          ' <div id="locomotive-section-page-header"'\
          ' class="locomotive-section my-awesome-header"'\
          ' data-locomotive-section-type="header">'\
            '<span id="page-header-section"></span>'\
            '<a>foo.png</a>'\
          '</div>' }

      end

    end

    context 'with page content' do
      let(:liquid_source) { 'built by <strong>{{ section.settings.brand }}</strong>' }

      context 'with on section' do

        context 'with simple type' do
          let(:content) {
            {
              header: {
                settings: { brand: 'Locomotive' },
                blocks:   []
              }
            }.deep_stringify_keys
          }

          it { is_expected.to eq 'Locomotive '\
            '<div id="locomotive-section-page-header"'\
            ' class="locomotive-section my-awesome-header"'\
            ' data-locomotive-section-type="header">'\
              '<span id="page-header-section"></span>'\
              'built by '\
              '<strong data-locomotive-editor-setting="section-page-header.brand">'\
                'Locomotive'\
              '</strong>'\
            '</div>' }
        end

        context 'with an id passed as an option' do

          let(:source) { 'Locomotive {% section header, id: "my_header" %}'}
          let(:content) {
            {
              'my_header': {
                settings: { brand: 'Locomotive' },
                blocks:   []
              }
            }.deep_stringify_keys
          }

          it { is_expected.to eq 'Locomotive '\
            '<div id="locomotive-section-page-my_header" '\
            'class="locomotive-section my-awesome-header" '\
            'data-locomotive-section-type="header">'\
              '<span id="page-my_header-section"></span>'\
              'built by '\
              '<strong data-locomotive-editor-setting="section-page-my_header.brand">'\
                'Locomotive'\
              '</strong>'\
            '</div>' }
        end

        context 'the same section twice on the page' do

          let(:source) { '{% section header, id: "first" %}{% section header, id: "second" %}' }

          it 'gives each one its editor setting attribute once' do
            expect(subject.scan('data-locomotive-editor-setting').size).to eq 2
            expect(subject).to include('<strong data-locomotive-editor-setting="section-page-first.brand">')
            expect(subject).to include('<strong data-locomotive-editor-setting="section-page-second.brand">')
          end

        end

        context 'with a quoted id in the tag and a saved anchor holding a quote and markup' do

          let(:source) { %(Locomotive {% section header, id: 'my"header' %}) }
          let(:content) {
            {
              'my"header': {
                anchor:   %(top" onclick="<x>&),
                settings: { brand: 'Locomotive' },
                blocks:   []
              }
            }.deep_stringify_keys
          }

          it { is_expected.to eq 'Locomotive '\
            '<div id="locomotive-section-page-my&quot;header" '\
            'class="locomotive-section my-awesome-header" '\
            'data-locomotive-section-type="header">'\
              '<span id="top&quot; onclick=&quot;&lt;x&gt;&amp;-section"></span>'\
              'built by '\
              '<strong data-locomotive-editor-setting="section-page-my&quot;header.brand">'\
                'Locomotive'\
              '</strong>'\
            '</div>' }
        end

      end
    end

    context 'the section has a syntax error inside its liquid template' do

      let(:liquid_source) { %(built by <a>\n\t<strong>{{ section.settings.brand }}{% if %}</strong></a>) }

      it 'raises a LiquidError naming the section, with its code' do
        expect { subject }.to raise_exception(Locomotive::Steam::LiquidError) { |error|
          expect(error.template_name).to eq 'sections--header'
          expect(error.line_number).to eq 2
          expect(error.code_lines).to include [2, "\t<strong>{{ section.settings.brand }}{% if %}</strong></a>"]
        }
      end

    end

    context 'rendering error (action) found in the section' do

      let(:live_editing)  { false }
      let(:liquid_source) { '{% action "Hello world" %}a.b(+}{% endaction %}' }
      let(:section)       { instance_double('section',
        name:           'Hero',
        type:           'header',
        liquid_source:  liquid_source,
        definition:     { settings: [], blocks: [] }
      )}

      it 'raises a TemplateError named after the section type' do
        expect { subject }.to raise_exception(Locomotive::Steam::TemplateError) { |error|
          expect(error.template_name).to eq 'sections--header'
        }
      end
    end

  end

  describe 'a section type holding two dashes' do

    let(:live_editing) { false }
    let(:source)       { "{% section 'hero--dark_x' %}" }

    def section_named(slug, liquid_source)
      instance_double('Section', slug: slug, type: slug, liquid_source: liquid_source,
                                 definition: { 'type' => slug, 'settings' => [], 'blocks' => [] })
    end

    before do
      allow(finder).to receive(:find).with('hero--dark_x').and_return(section_named('hero--dark_x', 'dark hero'))
      allow(finder).to receive(:find).with('hero').and_return(section_named('hero', 'plain hero'))
    end

    it 'renders its own template' do
      output = render_template(source, context)

      expect(output).to include 'dark hero'
      expect(output).not_to include 'plain hero'
    end

  end

  describe 'a section template nested too deep' do

    let(:live_editing)  { false }
    let(:source)        { "{% section 'deep' %}" }
    let(:liquid_source) { ('{% if true %}' * 101) + 'deep' + ('{% endif %}' * 101) }
    let(:section)       { instance_double('Section', slug: 'deep', type: 'deep', liquid_source: liquid_source,
                                                     definition: { 'type' => 'deep', 'settings' => [], 'blocks' => [] }) }

    before { allow(finder).to receive(:find).with('deep').and_return(section) }

    it 'keeps the Liquid error and names the section template' do
      expect { render_template(source, context) }.to raise_error(::Liquid::StackLevelError) { |error|
        expect(error.template_name).to eq 'sections--deep'
      }
    end

  end

  describe 'an error in the second of two sections' do

    let(:live_editing) { false }
    let(:source)       { "{% section 'first' %}{% section 'second' %}" }

    def section_typed(type, liquid_source)
      instance_double('Section', slug: type, type: type, liquid_source: liquid_source,
                                 definition: { 'type' => type, 'settings' => [], 'blocks' => [] })
    end

    before do
      allow(finder).to receive(:find).with('first').and_return(section_typed('first', 'first section'))
      allow(finder).to receive(:find).with('second').and_return(section_typed('second', '{% action "Hello world" %}a.b(+}{% endaction %}'))
    end

    it 'is named after the second section' do
      expect { render_template(source, context) }.to raise_error(Locomotive::Steam::TemplateError) { |error|
        expect(error.template_name).to eq 'sections--second'
      }
    end

  end

  describe 'an error in a snippet a section includes by a variable' do

    let(:live_editing)   { false }
    let(:assigns)        { { 'page' => page, 'card' => 'broken_card' } }
    let(:snippet_finder) { instance_double('SnippetFinder') }
    let(:file_system)    { Locomotive::Steam::Liquid::FileSystem.new(section_finder: finder, snippet_finder: snippet_finder) }
    let(:source)         { "{% section 'holder' %}" }
    let(:section)        { instance_double('Section', slug: 'holder', type: 'holder', liquid_source: '{% include card %}',
                                                      definition: { 'type' => 'holder', 'settings' => [], 'blocks' => [] }) }

    before do
      allow(finder).to receive(:find).with('holder').and_return(section)
      allow(snippet_finder).to receive(:find).with('broken_card').and_return(instance_double('Snippet', liquid_source: '{% if %}'))
    end

    it 'keeps the name of the snippet' do
      expect { render_template(source, context) }.to raise_error(Locomotive::Steam::LiquidError) { |error|
        expect(error.template_name).to eq 'broken_card'
      }
    end

  end

  describe 'the template name of the context' do

    let(:live_editing)  { false }
    let(:source)        { "{% section 'hero' %}" }
    let(:section)       { instance_double('Section', slug: 'hero', type: 'hero', liquid_source: liquid_source,
                                                     definition: { 'type' => 'hero', 'settings' => [], 'blocks' => [] }) }

    before do
      allow(finder).to receive(:find).with('hero').and_return(section)
      context.template_name = 'pages/index.liquid'
    end

    context 'after a section renders' do

      let(:liquid_source) { 'hero' }

      it 'is the one before the section' do
        render_template(source, context)

        expect(context.template_name).to eq 'pages/index.liquid'
      end

    end

    context 'after a section fails' do

      let(:liquid_source) { '{% action "Hello world" %}a.b(+}{% endaction %}' }

      it 'is the one before the section, while the error names the section' do
        expect { render_template(source, context) }.to raise_error(Locomotive::Steam::TemplateError) { |error|
          expect(error.template_name).to eq 'sections--hero'
        }

        expect(context.template_name).to eq 'pages/index.liquid'
      end

    end

  end

  describe "a context without Steam's template factory" do

    let(:live_editing) { false }
    let(:registers)    { { services: services, live_editing: live_editing, file_system: file_system } }
    let(:source)       { "{% section 'plain' %}" }
    let(:section)      { instance_double('Section', slug: 'plain', type: 'plain', liquid_source: liquid_source,
                                                    definition: { 'type' => 'plain', 'settings' => [], 'blocks' => [] }) }

    before { allow(finder).to receive(:find).with('plain').and_return(section) }

    context 'a section that parses' do

      let(:liquid_source) { 'plain section' }

      it 'renders it' do
        expect(render_template(source, context)).to include 'plain section'
      end

    end

    context 'a section with a syntax error' do

      let(:liquid_source) { "plain\n{% if %}" }

      it 'raises the Liquid error, naming the section, without its code' do
        expect { render_template(source, context) }.to raise_error(::Liquid::SyntaxError) { |error|
          expect(error.template_name).to eq 'sections--plain'
          expect(error).not_to respond_to(:code_lines)
        }
      end

    end

  end

end

