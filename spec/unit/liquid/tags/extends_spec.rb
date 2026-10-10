require 'spec_helper'

describe Locomotive::Steam::Liquid::Tags::Extends do

  describe 'unit bevahiors' do

    before { ::Liquid::Environment.default.file_system = ::Liquid::LayoutFileSystem.new }

    before do
      allow_any_instance_of(described_class).to receive(:parse_parent_template) do |instance|
        ::Liquid::Template.parse(
          ::Liquid::Environment.default.file_system.read_template_file(
            instance.instance_variable_get(:@template_name), {}
          ),
          instance.parse_context
        )
      end
    end

    let(:assigns) { {} }
    subject { render_template(source, ::Liquid::Context.new(assigns)) }

    context 'the template uses a wrong syntax of extends' do
      let(:source) { '{% extends %}' }
      it { expect { subject }.to raise_exception("Liquid syntax error (line 1): Syntax Error in 'extends' - Valid syntax: extends <page_handle_or_parent_keyword>") }
    end

    context 'the template uses a endtag' do
      let(:source) { '{% extends base %}{% endextends %}' }
      it { is_expected.to eq '<body>base</body>' }
    end

    context 'the template has a block' do
      let(:source) { ::Liquid::Environment.default.file_system.read_template_file('page_with_title', nil) }
      it { is_expected.to eq '<body><h1>Hello</h1><p>Lorem ipsum</p></body>' }
    end

    context 'the template extends another template' do
      let(:source) { '{% extends base %}' }
      it { is_expected.to eq '<body>base</body>' }
    end

    context 'the template extends an inherited template' do
      let(:source) { '{% extends inherited %}' }
      it { is_expected.to eq '<body>base</body>' }
    end

    context 'the template can pass variables to the parent template' do
      let(:assigns) { { 'name' => 'Macbook' } }
      let(:source) { '{% extends product %}' }
      it { is_expected.to eq '<body><h1>Our product: Macbook</h1></body>' }
    end

    context 'the template can pass variables to the inherited parent template' do
      let(:assigns) { { 'name' => 'PC' } }
      let(:source) { '{% extends product_with_warranty %}' }
      it { is_expected.to eq '<body><h1>Our product: PC</h1><p>mandatory warranty</p></body>' }
    end

    context 'the template does not render statements outside blocks' do
      let(:source) { '{% extends base %} Hello world' }
      it { is_expected.to eq '<body>base</body>' }
    end

    context 'the template extends another template with a single block' do
      let(:source) { '{% extends page_with_title %}' }
      it { is_expected.to eq '<body><h1>Hello</h1><p>Lorem ipsum</p></body>' }
    end

    context 'the template overrides a block' do
      let(:source) { '{% extends page_with_title %}{% block title %}Sweet{% endblock %}' }
      it { is_expected.to eq '<body><h1>Sweet</h1><p>Lorem ipsum</p></body>' }
    end

    context 'the template has access to the content of the overriden_block' do
      let(:source) { '{% extends page_with_title %}{% block title %}{{ block.super }} world{% endblock %}' }
      it { is_expected.to eq '<body><h1>Hello world</h1><p>Lorem ipsum</p></body>' }
    end

    context 'the template accepts nested blocks' do
      let(:assigns) { { 'name' => 'iPhone' } }
      let(:source) { '{% extends product_with_static_price %}{% block info/price %}{{ block.super }}<p>(not on sale)</p>{% endblock %}' }
      it { is_expected.to eq '<body><h1>Our product: iPhone</h1><h2>Some info</h2><p>$42.00</p><p>(not on sale)</p></body>' }
    end

  end

  describe 'in Steam' do

    let(:source)      { '{% extends parent %} ' }
    let(:page)        { instance_double('Page', _id: 'about-us', title: 'About us') }
    let(:site)        { instance_double('Site', default_locale: :en) }
    let!(:listener)   { Liquid::SimpleEventsListener.new }
    let(:finder)      { Locomotive::Steam::ParentFinderService.new(instance_double('PageRepository', site: site, locale: :en)) }
    let(:parser)      { Locomotive::Steam::LiquidParserService.new(nil, nil) }
    let(:options)     { { parent_finder: finder, page: page, parser: parser } }

    before do
      expect(finder.repository).to receive(:parent_of).with(page).and_return(parent)
    end

    describe 'no parent page found' do

      let(:parent)    { nil }
      let(:template)  { parse_template(source, options) }

      it { expect { template }.to raise_exception Locomotive::Steam::Liquid::PageNotFound }

    end

    describe 'parent page exists' do

      let!(:template) { parse_template(source, options) }

      let(:parent) { instance_double('Index', _id: 'index', handle: nil, slug: nil, localized_attributes: { source: true, template: true }, source: { en: 'Hello world!' }, template: { en: nil }) }

      it { expect(listener.event_names.first).to eq 'steam.parse.extends' }
      it { expect(template.render).to eq 'Hello world!' }
      it { expect(options[:page]).to eq page }

      describe 'set the layout name' do

        let(:source) { '{% extends parent %}{% block message %}My layout: {{ layout_name }}{% endblock %}' }

        let(:parent) { instance_double('Index', _id: 'index', handle: nil, slug: 'index', localized_attributes: { source: true, template: true }, source: { en: 'Hello world! {% block message %}{% endblock %}' }, template: { en: nil }) }

        it { expect(template.render).to eq 'Hello world! My layout: index' }

        context 'the handle of the parent page exists' do

          let(:parent) { instance_double('Index', _id: 'index', handle: 'home', slug: 'index', localized_attributes: { source: true, template: true }, source: { en: 'Hello world! {% block message %}{% endblock %}' }, template: { en: nil }) }

          it { expect(template.render).to eq 'Hello world! My layout: home' }

        end

      end

    end

  end

  describe 'pages extending each other' do

    let(:site)   { instance_double('Site', default_locale: :en) }
    let(:finder) { Locomotive::Steam::ParentFinderService.new(instance_double('PageRepository', site: site, locale: :en)) }
    let(:parser) { Locomotive::Steam::LiquidParserService.new(nil, nil) }

    def page(fullpath, liquid_source, id: "id-#{fullpath}")
      instance_double('Page', _id: id, fullpath: fullpath, handle: fullpath, slug: fullpath,
                              liquid_source: liquid_source, template_path: "app/views/pages/#{fullpath}.liquid")
    end

    def parse(start)
      parse_template(start.liquid_source, parent_finder: finder, page: start, parser: parser)
    end

    def stub_parent(child, parent)
      allow(finder).to receive(:find).with(child, parent.fullpath).and_return(parent)
    end

    context 'in a loop' do

      let(:a) { page('cycle-a', "{% extends cycle-b %}\n{% block body %}A{% endblock %}") }
      let(:b) { page('cycle-b', "{% extends cycle-a %}\n{% block body %}B{% endblock %}") }

      before { stub_parent(a, b); stub_parent(b, a) }

      it 'raises an error naming the page that closes the loop, at its extends' do
        expect { parse(a) }.to raise_error(Locomotive::Steam::LiquidError) { |error|
          expect(error.message).to include 'Pages extend each other in a loop: cycle-a, cycle-b, cycle-a'
          expect(error.template_name).to eq 'app/views/pages/cycle-b.liquid'
          expect(error.line_number).to eq 1
        }
      end

    end

    context 'a page extending itself' do

      let(:a) { page('self-page', '{% extends self-page %}') }

      before { stub_parent(a, a) }

      it 'raises an error' do
        expect { parse(a) }.to raise_error(Locomotive::Steam::Liquid::CyclicExtends, /in a loop: self-page, self-page/)
      end

    end

    context 'reaching a page it went through under another path' do

      let(:a)     { page('home', '{% extends welcome %}', id: 'page-1') }
      let(:again) { page('welcome', '{% extends home %}', id: 'page-1') }

      before { stub_parent(a, again) }

      it 'raises an error, since it is the same page' do
        expect { parse(a) }.to raise_error(Locomotive::Steam::Liquid::CyclicExtends, /in a loop: home, welcome/)
      end

    end

    context 'a loop further up the chain' do

      let(:a) { page('a', '{% extends b %}') }
      let(:b) { page('b', '{% extends c %}') }
      let(:c) { page('c', '{% extends b %}') }

      before { stub_parent(a, b); stub_parent(b, c); stub_parent(c, b) }

      it 'names the pages of the loop only' do
        expect { parse(a) }.to raise_error(Locomotive::Steam::LiquidError, /in a loop: b, c, b\z/)
      end

    end

    context 'in a chain without a loop' do

      let(:a) { page('a', "{% extends b %}{% block body %}A{% endblock %}") }
      let(:b) { page('b', "{% extends c %}") }
      let(:c) { page('c', "<c>{% block body %}C{% endblock %}</c>") }

      before { stub_parent(a, b); stub_parent(b, c) }

      it 'renders the page through its ancestors' do
        expect(parse(a).render).to eq '<c>A</c>'
      end

    end

  end

end
