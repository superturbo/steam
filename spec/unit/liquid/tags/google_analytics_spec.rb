require 'spec_helper'

describe Locomotive::Steam::Liquid::Tags::GoogleAnalytics do

  let(:context) { ::Liquid::Context.new({ 'ga_id' => '42' })}
  let(:source)  { "{% google_analytics 42 %}" }

  subject { render_template(source, context) }

  it { is_expected.to include %{<script async src="https://www.googletagmanager.com/gtag/js?id=42"></script>} }
  it { is_expected.to include %{gtag('config', "42");} }

  describe 'passing a string' do

    let(:source) { "{% google_analytics 'ga-42' %}" }

    it { is_expected.to include %{<script async src="https://www.googletagmanager.com/gtag/js?id=ga-42"></script>} }
    it { is_expected.to include %{gtag('config', "ga-42");} }

  end

  describe 'passing a variable' do

    let(:source) { "{% google_analytics ga_id %}" }

    it { is_expected.to include %{<script async src="https://www.googletagmanager.com/gtag/js?id=42"></script>} }
    it { is_expected.to include %{gtag('config', "42");} }

  end

  describe 'without an account id' do

    let(:source) { "{% google_analytics ga_id %}" }

    [nil, false, '', '   ', []].each do |blank|
      context "given #{blank.inspect}" do
        let(:context) { ::Liquid::Context.new({ 'ga_id' => blank }) }
        it { is_expected.to eq '' }
      end
    end

  end

  describe 'an account id with markup or quotes' do

    let(:account_id) { %{x"><script>alert(1)</script>'&\u2028y} }
    let(:context)    { ::Liquid::Context.new({ 'ga_id' => account_id }) }
    let(:source)     { "{% google_analytics ga_id %}" }

    around do |example|
      encoding   = ActiveSupport::JSON::Encoding
      entities   = encoding.escape_html_entities_in_json
      separators = encoding.escape_js_separators_in_json

      encoding.escape_html_entities_in_json = false
      encoding.escape_js_separators_in_json = false
      example.run
    ensure
      encoding.escape_html_entities_in_json = entities
      encoding.escape_js_separators_in_json = separators
    end

    it 'stays the id parameter of the src URL' do
      src = subject[/src="([^"]*)"/, 1]

      expect(URI.decode_www_form(URI(src).query).to_h['id']).to eq account_id
      expect(subject.scan('<script').size).to eq 2
    end

    it 'stays a JavaScript string with the same value, even without ActiveSupport JSON escaping' do
      literal = subject[/gtag\('config', (.*)\);/, 1]

      expect(literal).not_to match(/[<>&\u2028\u2029]/)
      expect(JSON.parse(literal)).to eq account_id
      expect(subject.scan('</script>').size).to eq 2
    end

  end

  describe 'raises an error if the syntax is incorrect' do
    let(:source) { '{% google_analytics %}' }
    it { expect { subject }.to raise_exception(::Liquid::SyntaxError) }
  end

end
