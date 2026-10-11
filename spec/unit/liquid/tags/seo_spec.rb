require 'spec_helper'

describe Locomotive::Steam::Liquid::Tags::SEO do

  let(:page)          { nil }
  let(:content_entry) { nil }

  let(:site)      { liquid_instance_double('Site', name: 'Acme', seo_title: 'Acme (SEO)', meta_description: 'A short site description', meta_keywords: 'test only cat dog') }
  let(:assigns)   { { 'site' => site, 'page' => page, 'content_entry' => content_entry } }
  let(:context)   { ::Liquid::Context.new(assigns, {}, {}) }

  subject { render_template(source, context).strip }

  let(:html) { Nokogiri::HTML5(subject) }

  def meta(name)
    html.at_css(%(meta[name="#{name}"]))['content']
  end

  describe 'seo' do

    let(:source) { '{% seo %}' }
    it { is_expected.to include '<title>Acme (SEO)</title>' }
    it { is_expected.to include %Q[<meta name="description" content="A short site description">] }
    it { is_expected.to include %Q[<meta name="keywords" content="test only cat dog">] }

  end

  describe 'seo_title' do

    let(:source) { '{% seo_title %}' }

    describe 'no page' do

      it { is_expected.to eq '<title>Acme (SEO)</title>' }

      describe 'no seo_title site property' do

        let(:site) { liquid_instance_double('Site', name: 'Acme', seo_title: nil, meta_description: 'A short site description', meta_keywords: 'test only cat dog') }
        it { is_expected.to eq '<title>Acme</title>' }

      end

    end

    describe 'with a page' do

      let(:page) { liquid_instance_double('Page', seo_title: 'Snow!') }
      it { is_expected.to eq '<title>Snow!</title>' }

    end

    describe 'with a content entry' do

      let(:content_entry) { liquid_instance_double('Entry', seo_title: 'Snow!') }
      it { is_expected.to eq '<title>Snow!</title>' }

    end

    describe 'a title holding markup' do

      let(:title)         { 'Snow</title><script>alert(1)</script>' }
      let(:content_entry) { liquid_instance_double('Entry', seo_title: title) }

      it 'renders it as text, adding no element' do
        expect(html.css('script')).to be_empty
        expect(html.at_css('title').text).to eq title
      end

    end

    describe 'a title holding quotes' do

      let(:page) { liquid_instance_double('Page', seo_title: 'The "Snow" issue') }

      it 'keeps them' do
        expect(html.at_css('title').text).to eq 'The "Snow" issue'
      end

    end

    describe 'a site name holding markup' do

      let(:site) { liquid_instance_double('Site', name: 'Acme</title><script>alert(1)</script>', seo_title: nil, meta_description: nil, meta_keywords: nil) }

      it 'renders it as text, adding no element' do
        expect(html.css('script')).to be_empty
        expect(html.at_css('title').text).to eq 'Acme</title><script>alert(1)</script>'
      end

    end

  end

  describe 'seo_metadata' do

    let(:source) { '{% seo_metadata %}' }

    describe 'no page' do

      it { is_expected.to include %Q[<meta name="description" content="A short site description">] }
      it { is_expected.to include %Q[<meta name="keywords" content="test only cat dog">] }

    end

    describe 'with a page' do

      let(:page) { liquid_instance_double('Page', meta_description: "It's snowing", meta_keywords: 'snow') }
      it { expect(meta('description')).to eq "It's snowing" }
      it { expect(meta('keywords')).to eq 'snow' }

    end

    describe 'with a content entry' do

      let(:content_entry) { liquid_instance_double('Entry', meta_description: "It's snowing", meta_keywords: 'snow') }
      it { expect(meta('description')).to eq "It's snowing" }
      it { expect(meta('keywords')).to eq 'snow' }

    end

    describe 'metadata holding quotes and markup' do

      let(:description)   { 'Snow" onfocus="alert(1)"><script>alert(1)</script>' }
      let(:keywords)      { 'snow" onfocus="alert(1)' }
      let(:content_entry) { liquid_instance_double('Entry', meta_description: description, meta_keywords: keywords) }

      it 'renders them as attribute values, adding no element or attribute' do
        expect(html.css('script')).to be_empty
        expect(html.css('meta').map { |tag| tag.attributes.keys }).to eq [%w(name content)] * 2
        expect(meta('description')).to eq description
        expect(meta('keywords')).to eq keywords
      end

    end

  end

end
