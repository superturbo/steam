require 'spec_helper'

describe Locomotive::Steam::Liquid::Tags::AltPageLinks do

  let(:locale)          { 'en' }
  let(:assigns)         { { 'page' => drop, 'base_url' => 'https://www.example.com' } }
  let(:prefix_default)  { false }
  let(:services)        { Locomotive::Steam::Services.build_instance }
  let(:locales)         { %w(en) }
  let(:site)            { instance_double('Site', locales: locales, default_locale: 'en', prefix_default_locale: prefix_default) }
  let(:drop)            { Locomotive::Steam::Liquid::Drops::Page.new(page) }
  let(:page)            { liquid_instance_double('Index', index?: true, localized_attributes: { title: true, fullpath: true }, title: { en: 'Home', fr: 'Accueil' }, fullpath: { en: 'index', fr: 'index' }, templatized?: false) }
  let(:context)         { ::Liquid::Context.new(assigns, {}, { services: services, site: site, locale: locale }) }

  subject { render_template(source, context) }

  before { allow(services).to receive(:current_site).and_return(site) }

  describe 'default rendering' do

    let(:source) { '{% alt_page_links %}' }

    it 'renders an empty string if one single locale' do
      is_expected.to eq('')
    end

    context 'multilingual site' do

      let(:locales) { %w(en fr) }

      it { is_expected.to eq((<<-HTML
<link rel="alternate" hreflang="x-default" href="https://www.example.com/" />
<link rel="alternate" hreflang="en" href="https://www.example.com/" />
<link rel="alternate" hreflang="fr" href="https://www.example.com/fr" />
        HTML
        ).strip)
      }

      context 'the current locale is different from the default one' do

        let(:locale) { 'fr' }

        it 'has to be the same links' do
          is_expected.to eq((<<-HTML
<link rel="alternate" hreflang="x-default" href="https://www.example.com/" />
<link rel="alternate" hreflang="en" href="https://www.example.com/" />
<link rel="alternate" hreflang="fr" href="https://www.example.com/fr" />
        HTML
          ).strip)
        end

      end

      context 'the developer wants to pass an ending path (dynamic routing)' do

        let(:locale)  { 'fr' }
        let(:page)    { liquid_instance_double('News', index?: false, localized_attributes: { title: true, fullpath: true }, title: { en: 'News', fr: 'Actualités' }, fullpath: { en: 'news', fr: 'actualites' }, templatized?: false) }
        let(:assigns) { { 'page' => drop, 'base_url' => 'https://www.example.com', 'alt_page_links_ending_path' => '/2019/06' } }

        it 'has to be the same links' do
          is_expected.to eq((<<-HTML
<link rel="alternate" hreflang="x-default" href="https://www.example.com/news/2019/06" />
<link rel="alternate" hreflang="en" href="https://www.example.com/news/2019/06" />
<link rel="alternate" hreflang="fr" href="https://www.example.com/fr/actualites/2019/06" />
        HTML
          ).strip)
        end

      end

      context 'an ending path from a request parameter' do

        let(:locale)  { 'fr' }
        let(:page)    { liquid_instance_double('News', index?: false, localized_attributes: { title: true, fullpath: true }, title: { en: 'News', fr: 'Actualités' }, fullpath: { en: 'news', fr: 'actualites' }, templatized?: false) }
        let(:assigns) { { 'page' => drop, 'base_url' => 'https://www.example.com', 'params' => Locomotive::Steam::Liquid::Drops::Params.new('path' => '/2019?a=1&b=2') } }
        let(:source)  { '{% assign alt_page_links_ending_path = params.path %}{% alt_page_links %}' }

        it 'writes the parameter once' do
          hrefs = Nokogiri::HTML5.fragment(subject).css('link').map { |link| link['href'] }
          expect(hrefs).to eq ['https://www.example.com/news/2019?a=1&b=2', 'https://www.example.com/news/2019?a=1&b=2', 'https://www.example.com/fr/actualites/2019?a=1&b=2']
        end

      end

      context 'an ending path and a locale holding markup' do

        let(:ending)  { '/" onclick="alert(1)' }
        let(:locales) { ['en', 'x"y<b>'] }
        let(:page)    { liquid_instance_double('News', index?: false, localized_attributes: { title: true, fullpath: true }, title: { en: 'News', 'x"y<b>': 'News' }, fullpath: { en: 'news', 'x"y<b>': 'news' }, templatized?: false) }
        let(:assigns) { { 'page' => drop, 'base_url' => 'https://www.example.com', 'alt_page_links_ending_path' => ending } }

        it 'writes them as the values of the attributes of each link' do
          links = Nokogiri::HTML5.fragment(subject).css('link')

          expect(links.map { |link| link.attributes.keys }).to eq [%w(rel hreflang href)] * 3
          expect(links.map { |link| link['hreflang'] }).to eq ['x-default', 'en', 'x"y<b>']
          expect(links.map { |link| link['href'] }).to eq ["https://www.example.com/news#{ending}"] * 2 + ["https://www.example.com/x\"y<b>/news#{ending}"]
        end

      end

    end

  end

end
