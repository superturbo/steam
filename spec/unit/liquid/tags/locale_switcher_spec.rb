require 'spec_helper'

describe Locomotive::Steam::Liquid::Tags::LocaleSwitcher do

  let(:locale)          { 'en' }
  let(:assigns)         { { 'page' => drop } }
  let(:prefix_default)  { false }
  let(:services)        { Locomotive::Steam::Services.build_instance }
  let(:site)            { instance_double('Site', locales: %w(en fr), default_locale: 'en', prefix_default_locale: prefix_default) }
  let(:drop)            { Locomotive::Steam::Liquid::Drops::Page.new(page) }
  let(:page)            { liquid_instance_double('Index', localized_attributes: { title: true, fullpath: true }, title: { en: 'Home', fr: 'Accueil' }, fullpath: { en: 'index', fr: 'index' }, templatized?: false) }
  let(:context)         { ::Liquid::Context.new(assigns, {}, { services: services, site: site, locale: locale }) }

  subject { render_template(source, context) }

  before { allow(services).to receive(:current_site).and_return(site) }

  describe 'default rendering' do

    let(:source) { '{% locale_switcher %}' }
    it { is_expected.to eq '<div id="locale-switcher"><a href="/" class="en current">en</a> | <a href="/fr" class="fr">fr</a></div>' }

    context 'different current locale' do

      let(:locale) { 'fr' }
      it { is_expected.to eq '<div id="locale-switcher"><a href="/" class="en">en</a> | <a href="/fr" class="fr current">fr</a></div>' }

    end

    context 'prefix_default_locale is true' do

      let(:prefix_default) { true }
      it { is_expected.to eq '<div id="locale-switcher"><a href="/en" class="en current">en</a> | <a href="/fr" class="fr">fr</a></div>' }

    end

  end

  describe 'site locales holding markup' do

    let(:site)   { instance_double('Site', locales: ['en', 'x"y<b>'], default_locale: 'en', prefix_default_locale: prefix_default) }
    let(:page)   { liquid_instance_double('Index', localized_attributes: { title: true, fullpath: true }, title: { en: 'Home', 'x"y<b>': 'Home' }, fullpath: { en: 'index', 'x"y<b>': 'index' }, templatized?: false) }
    let(:source) { '{% locale_switcher %}' }

    it 'writes them as the text and the class of each link' do
      links = Nokogiri::HTML5(subject).css('a')

      expect(links.map { |link| link.attributes.keys }).to eq [%w(href class)] * 2
      expect(links.map { |link| link['class'] }).to eq ['en current', 'x"y<b>']
      expect(links.map(&:text)).to eq ['en', 'x"y<b>']
    end

  end

  describe 'using the locale to display the links' do

    let(:source) { '{% locale_switcher label: "locale", sep: " - " %}' }
    it { is_expected.to eq '<div id="locale-switcher"><a href="/" class="en current">English</a> - <a href="/fr" class="fr">French</a></div>' }

  end

  describe 'using the title of the page to display the links' do

    let(:source) { '{% locale_switcher label: "title" %}' }
    it { is_expected.to eq '<div id="locale-switcher"><a href="/" class="en current">Home</a> | <a href="/fr" class="fr">Accueil</a></div>' }

    context 'a title and a path holding markup' do

      let(:page) { liquid_instance_double('Index', localized_attributes: { title: true, fullpath: true }, title: { en: 'Home</a><script>alert(1)</script>', fr: 'Home</a><script>alert(1)</script>' }, fullpath: { en: 'x" onclick="alert(1)', fr: 'x" onclick="alert(1)' }, templatized?: false) }

      it 'renders them as text and as one attribute, adding no element' do
        html = Nokogiri::HTML5(subject)

        expect(html.css('script')).to be_empty
        expect(html.css('a').map { |link| link.attributes.keys }).to eq [%w(href class)] * 2
        expect(html.css('a').map { |link| link['href'] }).to eq ['/x" onclick="alert(1)', '/fr/x" onclick="alert(1)']
        expect(html.css('a').map(&:text)).to eq ['Home</a><script>alert(1)</script>'] * 2
      end

    end

  end

  describe 'the page is templatized' do

    let(:assigns)     { { 'article' => entry_drop, 'page' => drop } }
    let(:entry_drop)  { Locomotive::Steam::Liquid::Drops::ContentEntry.new(entry) }
    let(:entry)       { liquid_instance_double('Article', _label: { en: 'Hello world', fr: 'Bonjour monde' }, _slug: { en: 'hello-world', fr: 'bonjour-monde' }, localized_attributes: { _label: true, _slug: true }) }
    let(:drop)        { Locomotive::Steam::Liquid::Drops::Page.new(page) }
    let(:page)        { liquid_instance_double('ArticleTemplate', title: 'Article template', fullpath: { en: 'my-articles/content_type_template', fr: 'mes-articles/content_type_template' }, content_entry: entry_drop.send(:_source), templatized?: true, localized_attributes: { fullpath: true }) }

    let(:source) { '{% locale_switcher label: "title" %}' }
    it { is_expected.to eq '<div id="locale-switcher"><a href="/my-articles/hello-world" class="en current">Hello world</a> | <a href="/fr/mes-articles/bonjour-monde" class="fr">Bonjour monde</a></div>' }

  end

end
