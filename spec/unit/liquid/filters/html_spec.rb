require 'spec_helper'

describe Locomotive::Steam::Liquid::Filters::Html do

  include Locomotive::Steam::Liquid::Filters::Base
  include Locomotive::Steam::Liquid::Filters::Html

  let(:asset_host)    { nil }
  let(:site)          { instance_double('Site', _id: 42, asset_host: asset_host) }
  let(:services)      { Locomotive::Steam::Services.build_instance }
  let(:context)       { instance_double('Context', registers: { services: services }) }

  let(:_theme_asset_url)        { services.theme_asset_url }
  let(:theme_asset_repository)  { services.repositories.theme_asset }

  before { services.repositories.theme_asset = EngineThemeAsset.new(nil, site) }

  before { allow(services).to receive(:current_site).and_return(site) }

  before { @context = context }

  describe '#auto_discovery_link_tag' do

    it 'writes the tag to display a rss/atom feed' do
      expect(auto_discovery_link_tag('/foo/bar')).to eq %(
        <link rel="alternate" type="application/rss+xml" title="RSS" href="/foo/bar" />
      ).strip

      expect(auto_discovery_link_tag('/foo/bar', 'rel:alternate2', 'type:atom', 'title:Hello world')).to eq %(
        <link rel="alternate2" type="atom" title="Hello world" href="/foo/bar" />
      ).strip
    end
  end

  describe '#theme_asset_url' do

    it 'returns the url to a JSON file' do
      expect(theme_asset_url('others/manifest.json')).to eq('/sites/42/theme/others/manifest.json')
    end

    it 'leaves the path it is given as it was, for the template to use again' do
      context = ::Liquid::Context.new({ 'path' => +'others/app.js?v=1' }, {}, { services: services })

      expect(render_template('{{ path | theme_asset_url }} {{ path | theme_asset_url }} {{ path }}', context))
        .to eq '/sites/42/theme/others/app.js?v=1 /sites/42/theme/others/app.js?v=1 others/app.js?v=1'
    end

  end

  describe '#stylesheet_url' do

    it 'returns an url for a stylesheet file' do
      result = "/sites/42/theme/stylesheets/main.css"
      expect(stylesheet_url('main.css')).to eq(result)
      expect(stylesheet_url('main')).to eq(result)
      expect(stylesheet_url(nil)).to eq('')
    end

    it 'returns an url for a stylesheet file with folder' do
      result = "/sites/42/theme/stylesheets/trash/main.css"
      expect(stylesheet_url('trash/main.css')).to eq(result)
    end

    it 'returns an url for a stylesheet file without touching the url that starts with "/"' do
      result = "/trash/main.css"
      expect(stylesheet_url('/trash/main.css')).to eq(result)
      expect(stylesheet_url('/trash/main')).to eq(result)
    end

    it 'returns an url for a stylesheet file without touching the url that starts with "http:"' do
      expect(stylesheet_url('http://cdn.example.com/trash/main.css')).to eq "http://cdn.example.com/trash/main.css"
    end

    it 'returns an url for a stylesheet file without touching the url that starts with "https:"' do
      expect(stylesheet_url('https://cdn.example.com/trash/main.css')).to eq "https://cdn.example.com/trash/main.css"
    end

    it 'returns an url for a stylesheet file with respect to URL-parameters' do
      result = "/sites/42/theme/stylesheets/main.css?v=42"
      expect(stylesheet_url('main.css?v=42')).to eq(result)
      expect(stylesheet_url('main?v=42')).to eq(result)
    end

    it 'returns a link tag for a stylesheet file' do
      result = "<link href=\"/sites/42/theme/stylesheets/main.css\" media=\"screen\" rel=\"stylesheet\" type=\"text/css\" />"
      expect(stylesheet_tag('main.css')).to eq(result)
      expect(stylesheet_tag('main')).to eq(result)
      expect(stylesheet_tag(nil)).to eq('')
    end

    it 'returns a link tag for a stylesheet file with folder' do
      result = "<link href=\"/sites/42/theme/stylesheets/trash/main.css\" media=\"screen\" rel=\"stylesheet\" type=\"text/css\" />"
      expect(stylesheet_tag('trash/main.css')).to eq(result)
    end

    it 'returns a link tag for a stylesheet file without touching the url that starts with "/"' do
      expect(stylesheet_tag('/trash/main.css')).to eq "<link href=\"/trash/main.css\" media=\"screen\" rel=\"stylesheet\" type=\"text/css\" />"
      expect(stylesheet_tag('/trash/main')).to eq "<link href=\"/trash/main.css\" media=\"screen\" rel=\"stylesheet\" type=\"text/css\" />"
    end

    it 'returns a link tag for a stylesheet file without touching the url that starts with "http:"' do
      expect(stylesheet_tag('http://cdn.example.com/trash/main.css')).to eq "<link href=\"http://cdn.example.com/trash/main.css\" media=\"screen\" rel=\"stylesheet\" type=\"text/css\" />"
    end

    it 'returns a link tag for a stylesheet file without touching the url that starts with "https:"' do
      expect(stylesheet_tag('https://cdn.example.com/trash/main.css')).to eq "<link href=\"https://cdn.example.com/trash/main.css\" media=\"screen\" rel=\"stylesheet\" type=\"text/css\" />"
    end

    it 'returns a link tag for a stylesheet stored in Amazon S3' do
      url = 'https://com.citrrus.locomotive.s3.amazonaws.com/sites/42/theme/stylesheets/bootstrap2.css'
      allow(_theme_asset_url).to receive(:build).and_return(url)
      result = "<link href=\"#{url}\" media=\"screen\" rel=\"stylesheet\" type=\"text/css\" />"
      expect(stylesheet_tag('bootstrap2.css')).to eq(result)
    end

    it 'returns a link tag for a stylesheet file and media attribute set to print' do
      result = "<link href=\"/sites/42/theme/stylesheets/main.css\" media=\"print\" rel=\"stylesheet\" type=\"text/css\" />"
      expect(stylesheet_tag('main.css','print')).to eq(result)
      expect(stylesheet_tag('main','print')).to eq(result)
      expect(stylesheet_tag(nil)).to eq('')
    end

    it 'returns a link tag for a stylesheet file with folder and media attribute set to print' do
      result = "<link href=\"/sites/42/theme/stylesheets/trash/main.css\" media=\"print\" rel=\"stylesheet\" type=\"text/css\" />"
      expect(stylesheet_tag('trash/main.css','print')).to eq(result)
    end

    it 'returns a link tag for a stylesheet file without touching the url that starts with "/" and media attribute set to print' do
      result = "<link href=\"/trash/main.css\" media=\"print\" rel=\"stylesheet\" type=\"text/css\" />"
      expect(stylesheet_tag('/trash/main.css','print')).to eq(result)
      expect(stylesheet_tag('/trash/main','print')).to eq(result)
    end

    it 'returns a link tag for a stylesheet file without touching the url that starts with "http:" and media attribute set to print' do
      expect(stylesheet_tag('http://cdn.example.com/trash/main.css', 'print')).to eq "<link href=\"http://cdn.example.com/trash/main.css\" media=\"print\" rel=\"stylesheet\" type=\"text/css\" />"
      expect(stylesheet_tag('http://cdn.example.com/trash/main', 'print')).to eq "<link href=\"http://cdn.example.com/trash/main\" media=\"print\" rel=\"stylesheet\" type=\"text/css\" />"
    end

    it 'returns a link tag for a stylesheet file without touching the url that starts with "https:" and media attribute set to print' do
      expect(stylesheet_tag('https://cdn.example.com/trash/main.css', 'print')).to eq "<link href=\"https://cdn.example.com/trash/main.css\" media=\"print\" rel=\"stylesheet\" type=\"text/css\" />"
      expect(stylesheet_tag('https://cdn.example.com/trash/main', 'print')).to eq "<link href=\"https://cdn.example.com/trash/main\" media=\"print\" rel=\"stylesheet\" type=\"text/css\" />"
    end

    describe 'with checksum' do

      around do |example|
        previous = Locomotive::Steam.configuration.theme_assets_checksum
        Locomotive::Steam.configuration.theme_assets_checksum = true
        example.run
      ensure
        Locomotive::Steam.configuration.theme_assets_checksum = previous
      end

      before do
        allow(theme_asset_repository).to receive(:checksums).and_return('stylesheets/main.css' => 42)
      end

      it 'returns an url with the checksum' do
        result = "/sites/42/theme/stylesheets/main.css?42"
        expect(stylesheet_url('main.css')).to eq(result)
      end

    end

  end

  describe '#javascript_url' do

    it 'returns an url for a javascript file' do
      result = "/sites/42/theme/javascripts/main.js"
      expect(javascript_url('main.js')).to eq(result)
      expect(javascript_url('main')).to eq(result)
      expect(javascript_url(nil)).to eq('')
    end

    it 'returns an url for a javascript file with folder' do
      result = "/sites/42/theme/javascripts/trash/main.js"
      expect(javascript_url('trash/main.js')).to eq(result)
      expect(javascript_url('trash/main')).to eq(result)
    end

    it 'returns an url for a javascript file without touching the url that starts with "/"' do
      result = "/trash/main.js"
      expect(javascript_url('/trash/main.js')).to eq(result)
      expect(javascript_url('/trash/main')).to eq(result)
    end

    it 'returns an url for a javascript file without touching the url that starts with "http:"' do
      expect(javascript_url('http://cdn.example.com/trash/main.js')).to eq "http://cdn.example.com/trash/main.js"
      expect(javascript_url('http://cdn.example.com/trash/main')).to eq "http://cdn.example.com/trash/main"
    end

    it 'returns an url for a javascript file without touching the url that starts with "https:"' do
      expect(javascript_url('https://cdn.example.com/trash/main.js')).to eq "https://cdn.example.com/trash/main.js"
      expect(javascript_url('https://cdn.example.com/trash/main')).to eq "https://cdn.example.com/trash/main"
    end

    it 'returns an url for a javascript file with respect to URL-parameters' do
      expect(javascript_url('main.js?v=42')).to eq "/sites/42/theme/javascripts/main.js?v=42"
    end

    it 'returns a script tag for a javascript file' do
      result = %{<script src="/sites/42/theme/javascripts/main.js" type="text/javascript" ></script>}
      expect(javascript_tag('main.js')).to eq(result)
      expect(javascript_tag('main')).to eq(result)
      expect(javascript_tag(nil)).to eq('')
    end

    it 'returns a script tag for a javascript file with folder' do
      result = %{<script src="/sites/42/theme/javascripts/trash/main.js" type="text/javascript" ></script>}
      expect(javascript_tag('trash/main.js')).to eq(result)
      expect(javascript_tag('trash/main')).to eq(result)
    end

    it 'returns a script tag for a javascript file without touching the url that starts with "/"' do
      result = %{<script src="/trash/main.js" type="text/javascript" ></script>}
      expect(javascript_tag('/trash/main.js')).to eq(result)
      expect(javascript_tag('/trash/main')).to eq(result)
    end

    it 'returns a script tag for a javascript file without touching the url that starts with "http:"' do
      expect(javascript_tag('http://cdn.example.com/trash/main.js')).to eq %{<script src="http://cdn.example.com/trash/main.js" type="text/javascript" ></script>}
      expect(javascript_tag('http://cdn.example.com/trash/main')).to eq %{<script src="http://cdn.example.com/trash/main" type="text/javascript" ></script>}
    end

    it 'returns a script tag for a javascript file without touching the url that starts with "https:"' do
      expect(javascript_tag('https://cdn.example.com/trash/main.js')).to eq %{<script src="https://cdn.example.com/trash/main.js" type="text/javascript" ></script>}
      expect(javascript_tag('https://cdn.example.com/trash/main')).to eq %{<script src="https://cdn.example.com/trash/main" type="text/javascript" ></script>}
    end

    it 'returns a script tag for a javascript file with "defer" option' do
      result = %{<script src="https://cdn.example.com/trash/main.js" type="text/javascript" defer="defer" ></script>}
      expect(javascript_tag('https://cdn.example.com/trash/main.js', ['defer:defer'])).to eq(result)
    end

  end

  describe '#theme_image_url' do

    it 'returns an image url for a given theme file without parameters' do
      expect(theme_image_url('foo.jpg')).to eq "/sites/42/theme/images/foo.jpg"
    end

    it 'returns an image tag for a given theme file without parameters' do
      expect(theme_image_tag('foo.jpg')).to eq "<img src=\"/sites/42/theme/images/foo.jpg\" >"
    end

    it 'returns an image tag for a given theme file with size' do
      expect(theme_image_tag('foo.jpg', 'width:100', 'height:100')).to eq("<img src=\"/sites/42/theme/images/foo.jpg\" height=\"100\" width=\"100\" >")
    end

    it 'returns an image tag without parameters' do
      expect(image_tag('foo.jpg')).to eq("<img src=\"foo.jpg\" >")
    end

    it 'returns an image tag for a file with a leading slash' do
      expect(image_tag('/foo.jpg')).to eq "<img src=\"/foo.jpg\" >"
    end

    it 'returns an image tag with size' do
      expect(image_tag('foo.jpg', 'width:100', 'height:50')).to eq("<img src=\"foo.jpg\" height=\"50\" width=\"100\" >")
    end

  end

  describe '#flash_tag' do

    it 'returns a flash tag without parameters' do
      expect(flash_tag('foo.flv')).to eq(%{
<object>
  <param name="movie" value="foo.flv">
  <embed src="foo.flv">
  </embed>
</object>
      }.strip)
    end

    it 'returns a flash tag with size' do
      expect(flash_tag('foo.flv', 'width:100', 'height:50')).to eq(%{
<object height=\"50\" width=\"100\">
  <param name="movie" value="foo.flv">
  <embed src="foo.flv" height=\"50\" width=\"100\">
  </embed>
</object>
      }.strip)
    end

  end

  context 'asset_host' do

    let(:asset_host) { 'http://asset.dev' }

    it 'returns an url for a stylesheet file with respect to URL-parameters' do
      result = "http://asset.dev/sites/42/theme/stylesheets/main.css?v=42"
      expect(stylesheet_url('main.css?v=42')).to eq(result)
      expect(stylesheet_url('main?v=42')).to eq(result)
    end

    it 'returns a link tag for a stylesheet file' do
      result = "<link href=\"http://asset.dev/sites/42/theme/stylesheets/main.css\" media=\"screen\" rel=\"stylesheet\" type=\"text/css\" />"
      expect(stylesheet_tag('main.css')).to eq(result)
      expect(stylesheet_tag('main')).to eq(result)
      expect(stylesheet_tag(nil)).to eq('')
    end

    it 'returns a link tag for a stylesheet file with folder' do
      result = "<link href=\"http://asset.dev/sites/42/theme/stylesheets/trash/main.css\" media=\"screen\" rel=\"stylesheet\" type=\"text/css\" />"
      expect(stylesheet_tag('trash/main.css')).to eq(result)
    end

    it 'returns an url for a javascript file with respect to URL-parameters' do
      expect(javascript_url('main.js?v=42')).to eq "http://asset.dev/sites/42/theme/javascripts/main.js?v=42"
    end

    it 'returns a script tag for a javascript file' do
      result = %{<script src="http://asset.dev/sites/42/theme/javascripts/main.js" type="text/javascript" ></script>}
      expect(javascript_tag('main.js')).to eq(result)
      expect(javascript_tag('main')).to eq(result)
      expect(javascript_tag(nil)).to eq('')
    end

    it 'returns a script tag for a javascript file with folder' do
      result = %{<script src="http://asset.dev/sites/42/theme/javascripts/trash/main.js" type="text/javascript" ></script>}
      expect(javascript_tag('trash/main.js')).to eq(result)
      expect(javascript_tag('trash/main')).to eq(result)
    end

    it 'returns an image url for a given theme file without parameters' do
      expect(theme_image_url('foo.jpg')).to eq "http://asset.dev/sites/42/theme/images/foo.jpg"
    end

    it 'returns an image tag for a given theme file without parameters' do
      expect(theme_image_tag('foo.jpg')).to eq "<img src=\"http://asset.dev/sites/42/theme/images/foo.jpg\" >"
    end

    it 'returns an image tag for a given theme file with size' do
      expect(theme_image_tag('foo.jpg', 'width:100', 'height:100')).to eq("<img src=\"http://asset.dev/sites/42/theme/images/foo.jpg\" height=\"100\" width=\"100\" >")
    end

  end

  describe 'values holding markup' do

    let(:text) { 'x" onclick="alert(1)' }

    def attributes_of(html, selector)
      Nokogiri::HTML5.fragment(html).css(selector).map { |element| element.attributes.transform_values(&:value) }
    end

    it 'writes them as the attribute values of auto_discovery_link_tag' do
      html = auto_discovery_link_tag(text, "rel:#{text}", "type:#{text}", "title:#{text}")
      expect(attributes_of(html, 'link')).to eq [{ 'rel' => text, 'type' => text, 'title' => text, 'href' => text }]
    end

    it 'writes them as the attribute values of stylesheet_tag' do
      html = stylesheet_tag('/main.css?x&lt;b', text)
      expect(attributes_of(html, 'link')).to eq [{ 'href' => '/main.css?x&lt;b', 'media' => text, 'rel' => 'stylesheet', 'type' => 'text/css' }]
    end

    it 'writes them as the attribute values of javascript_tag' do
      html = javascript_tag('/main.js?x&lt;b', "defer:#{text}")
      expect(attributes_of(html, 'script')).to eq [{ 'src' => '/main.js?x&lt;b', 'type' => 'text/javascript', 'defer' => text }]
    end

    it 'writes them as the attribute values of theme_image_tag and image_tag' do
      expect(attributes_of(theme_image_tag("/#{text}.jpg", "alt:#{text}"), 'img')).to eq [{ 'src' => theme_image_url("/#{text}.jpg"), 'alt' => text }]
      expect(attributes_of(image_tag(text, "alt:#{text}"), 'img')).to eq [{ 'src' => text, 'alt' => text }]
    end

    it 'writes them as the attribute values of flash_tag' do
      html = flash_tag(text, "width:#{text}")
      expect(attributes_of(html, 'object, param, embed')).to eq [{ 'width' => text }, { 'name' => 'movie', 'value' => text }, { 'src' => text, 'width' => text }]
    end

  end

  describe 'options of a tag' do

    let(:params)  { Locomotive::Steam::Liquid::Drops::Params.new('image' => '/i.jpg?w=1&h=2') }
    let(:assigns) { { 'params' => params, 'title' => 'Kaunas onload=alert(1) x: old town' } }

    def render_img(source)
      Nokogiri::HTML5.fragment(render_template(source, ::Liquid::Context.new(assigns))).at_css('img').attributes.transform_values(&:value)
    end

    it 'keeps the names the template writes, with values holding colons' do
      expect(image_tag('/m.jpg', 'style:width:100px', 'role:img')).to eq '<img src="/m.jpg" role="img" style="width:100px" >'
    end

    it 'reads the name up to the first colon' do
      expect(render_img(%({% capture option %}\nalt:{{ title }}\n{% endcapture %}{{ '/m.jpg' | image_tag: option }}))).to eq('src' => '/m.jpg', 'alt' => 'Kaunas onload=alert(1) x: old town')
    end

    it 'takes the raw value of a request parameter' do
      expect(render_img(%({{ params.unsafe.image | image_tag }}))).to eq('src' => '/i.jpg?w=1&h=2')
    end

  end

  describe 'a request parameter or a safe_url result as the input' do

    let(:params)  { Locomotive::Steam::Liquid::Drops::Params.new('url' => '/i.jpg?w=1&h=2', 'css' => '/main.css?a=1&b=2', 'js' => '/main.js?a=1&b=2', 'media' => 'a&b', 'option' => 'alt:A&B', 'rel' => 'rel:a&b', 'type' => 'type:c&d', 'title' => 'title:A&B') }
    let(:assigns) { { 'params' => params } }

    def render_html(source)
      Nokogiri::HTML5.fragment(render_template(source, ::Liquid::Context.new(assigns, {}, { services: services })))
    end

    it 'is written once by image_tag' do
      expect(render_html('{{ params.url | image_tag }}').at_css('img')['src']).to eq '/i.jpg?w=1&h=2'
    end

    it 'is written once by theme_image_tag' do
      expect(render_html('{{ params.url | theme_image_tag }}').at_css('img')['src']).to eq theme_image_url('/i.jpg?w=1&h=2')
    end

    it 'is written once by stylesheet_tag' do
      link = render_html('{{ params.css | stylesheet_tag: params.media }}').at_css('link')
      expect([link['href'], link['media']]).to eq ['/main.css?a=1&b=2', 'a&b']
    end

    it 'is written once by javascript_tag and flash_tag' do
      expect(render_html('{{ params.js | javascript_tag }}').at_css('script')['src']).to eq '/main.js?a=1&b=2'
      expect(render_html('{{ params.url | flash_tag }}').css('param, embed').map { |element| element['value'] || element['src'] }).to eq ['/i.jpg?w=1&h=2'] * 2
    end

    it 'is written once by auto_discovery_link_tag' do
      expect(render_html('{{ params.url | auto_discovery_link_tag }}').at_css('link')['href']).to eq '/i.jpg?w=1&h=2'
    end

    it 'writes the value of an escaped option once' do
      expect(render_html(%({{ '/i.jpg' | image_tag: params.option }})).at_css('img')['alt']).to eq 'A&B'
    end

    it 'writes the escaped options of auto_discovery_link_tag once' do
      link = render_html(%({{ '/feed' | auto_discovery_link_tag: params.rel, params.type, params.title }})).at_css('link')
      expect([link['rel'], link['type'], link['title']]).to eq ['a&b', 'c&d', 'A&B']
    end

    it 'is written once through a url filter' do
      expect(render_html('{{ params.url | theme_image_url | image_tag }}').at_css('img')['src']).to eq theme_image_url('/i.jpg?w=1&h=2')
      expect(render_html('{{ params.url | theme_asset_url | image_tag }}').at_css('img')['src']).to eq theme_asset_url('/i.jpg?w=1&h=2')
    end

    it 'stays escaped where a filter returns a url into the template' do
      assigns['params'] = Locomotive::Steam::Liquid::Drops::Params.new('url' => '"><b>x</b>')
      expect(render_html('{{ params.url | theme_image_url }}').css('b')).to be_empty
    end

    it 'is checked once by safe_url and written once as the url it checked' do
      expect(render_template('{{ params.url | safe_url }}', ::Liquid::Context.new(assigns))).to eq '/i.jpg?w=1&amp;h=2'
      expect(render_html('{{ params.url | safe_url | image_tag }}').at_css('img')['src']).to eq '/i.jpg?w=1&h=2'
      expect(render_html("{{ '  /i.jpg?w=1&h=2 ' | safe_url | image_tag }}").at_css('img')['src']).to eq '/i.jpg?w=1&h=2'
    end

  end

  describe '#safe_url' do

    it 'returns a plain empty string for a refused url' do
      expect(safe_url('javascript:alert(1)')).to be_an_instance_of(String).and eq ''
    end

    it 'passes allowlisted schemes through (escaped)' do
      expect(safe_url('http://x')).to eq 'http://x'
      expect(safe_url('https://x')).to eq 'https://x'
      expect(safe_url('mailto:a@b.com')).to eq 'mailto:a@b.com'
      expect(safe_url('tel:+123')).to eq 'tel:+123'
    end

    it 'passes relative, anchor, query and protocol-relative urls' do
      expect(safe_url('/foo/bar')).to eq '/foo/bar'
      expect(safe_url('foo/bar')).to eq 'foo/bar'
      expect(safe_url('#section')).to eq '#section'
      expect(safe_url('?q=1')).to eq '?q=1'
      expect(safe_url('//cdn.example.com')).to eq '//cdn.example.com'
    end

    it 'strips surrounding whitespace before deciding' do
      expect(safe_url('  http://x')).to eq 'http://x'
      expect(safe_url('  javascript:x')).to eq ''
    end

    it 'rejects non-allowlisted schemes (case-insensitive)' do
      expect(safe_url('javascript:alert(1)')).to eq ''
      expect(safe_url('data:text/html,x')).to eq ''
      expect(safe_url('vbscript:x')).to eq ''
      expect(safe_url('JavaScript:alert(1)')).to eq ''
    end

    it 'rejects any value carrying an ASCII control character' do
      expect(safe_url("java\tscript:x")).to eq ''
      expect(safe_url("java\nscript:x")).to eq ''
      expect(safe_url("/foo\tbar")).to eq ''
      expect(safe_url("http://x\0")).to eq ''
      expect(safe_url("http://x\x7F")).to eq ''
    end

    it 'html-escapes the result so it is safe inside a quoted attribute' do
      expect(safe_url('http://x?a=1&b=2')).to eq 'http://x?a=1&amp;b=2'
      expect(safe_url('http://x" onclick="alert(1)')).to eq 'http://x&quot; onclick=&quot;alert(1)'
      expect(safe_url("http://x' onclick='alert(1)")).to eq 'http://x&#39; onclick=&#39;alert(1)'
    end

    it 'keeps an entity-encoded scheme inert' do
      expect(safe_url('javascript&#58;alert(1)')).to eq 'javascript&amp;#58;alert(1)'
    end

    it 'returns an empty string for nil or blank input' do
      expect(safe_url(nil)).to eq ''
      expect(safe_url('')).to eq ''
      expect(safe_url('   ')).to eq ''
    end

    it 'is registered and usable through Liquid' do
      expect(::Liquid::Template.parse("{{ 'javascript:alert(1)' | safe_url }}").render).to eq ''
    end

  end

  class EngineThemeAsset < Locomotive::Steam::ThemeAssetRepository
    def url_for(path)
      ['', 'sites', site._id.to_s, 'theme', path].join('/')
    end
  end

end
