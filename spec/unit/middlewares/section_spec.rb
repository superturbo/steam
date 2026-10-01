require 'spec_helper'

require_relative '../../../lib/locomotive/steam/middlewares/thread_safe'
require_relative '../../../lib/locomotive/steam/middlewares/concerns/helpers'
require_relative '../../../lib/locomotive/steam/middlewares/concerns/liquid_context'
require_relative '../../../lib/locomotive/steam/middlewares/section'

describe Locomotive::Steam::Middlewares::Section do

  let(:app)             { ->(env) { [200, env, 'app'] }}
  let(:url)             { 'http://example.com/foo/bar' }
  let(:env)             { env_for(url, 'steam.site' => site) }

  let(:site_drop)       { liquid_instance_double('SiteDrop', sections_content: { 'header' => { 'settings' => { 'name' => 'this should not be rendered in middleware' } } }) }
  let(:page_drop)       { liquid_instance_double('PageDrop', sections_content: { 'header' => { 'settings' => { 'name' => 'this should not be rendered in middleware' } } }) }
  let(:site)            { instance_double('Site', default_locale: 'en', locales: ['en'], to_liquid: site_drop) }
  let(:page)            { instance_double('Page', default_locale: 'en', locales: ['en'], to_liquid: page_drop) }
  let(:section)         { instance_double('Section', type: 'header', definition: {}, liquid_source: 'Here some {{ section.settings.name }}') }
  let(:section_finder)  { instance_double('SectionFinderService') }
  let(:repositories)    { instance_double('Repositories')}

  let(:services)        { instance_double(
                          'Services',
                          section_finder: section_finder,
                          snippet_finder: nil,
                          repositories: repositories,
                          locale: 'en')
                        }

  let(:body) { '' }
  let(:type) { 'header' }
  let(:live_editing) { true }

  before do
    env['rack.input']             = StringIO.new(body)
    env['steam.page']             = page
    env['steam.services']         = services
    env['steam.locale']           = :en
    env['steam.liquid_registers'] = {}
    env['steam.liquid_assigns']   = {}
    env['steam.request']          = Rack::Request.new(env)
    env['steam.live_editing']     = live_editing
    env['steam.request'].add_header('HTTP_LOCOMOTIVE_SECTION_TYPE', type)
    allow(section_finder).to receive(:find).and_return(nil)
    allow(section_finder).to receive(:find).with('header').and_return(section)
  end

  subject do
    middleware = described_class.new(app)
    middleware.call(env)
  end

  it "renders the section's default content for an empty body" do
    is_expected.to eq [
      200,
      { "content-type" => "text/html" },
      [%(<div id="locomotive-section-header" class="locomotive-section" data-locomotive-section-type="header"><span id="header-section"></span>Here some </div>)]
    ]
  end

  context 'outside live editing' do

    let(:live_editing) { nil }

    it 'leaves the request to the next middleware' do
      expect(section_finder).not_to receive(:find)
      is_expected.to eq [200, env, 'app']
    end

  end

  ['unknown', "header' %}{{ 6 | times: 7 }}{% section 'header"].each do |name|

    context "with #{name.inspect}, the type of no section" do

      let(:type) { name }

      it 'answers 404 without parsing Liquid' do
        expect(Locomotive::Steam::Liquid::Template).not_to receive(:parse)
        is_expected.to eq [404, { 'content-type' => 'text/plain' }, ['Section not found']]
      end

    end

  end

  context 'with the slug of an existing section that reads as Liquid' do

    let(:type)    { "header' %}{{ 6 | times: 7 }}{% section 'header" }
    let(:section) { instance_double('Section', type: type, definition: {}, liquid_source: 'Here some {{ section.settings.name }}') }

    before { allow(section_finder).to receive(:find).with(type).and_return(section) }

    it 'renders that section, the slug only naming it' do
      status, _, body = subject

      expect(status).to eq 200
      expect(body.first).to include('Here some ')
      expect(body.first).not_to include('42')
    end

  end

  context 'a section whose template has a Liquid syntax error' do

    let(:section) { instance_double('Section', type: 'header', definition: {}, liquid_source: "Here some\n{% if %}") }

    it 'raises a LiquidError naming the section template, as the section tag does' do
      expect { subject }.to raise_error(Locomotive::Steam::LiquidError) do |error|
        expect(error.template_name).to eq 'sections--header'
        expect(error.line_number).to eq 2
      end
    end

  end

  context 'a request body without the content of the section' do

    let(:body) { '{}' }

    it 'renders the content the page holds for the section' do
      is_expected.to eq [
        200,
        { "content-type" => "text/html" },
        [%(<div id="locomotive-section-page-header" class="locomotive-section" data-locomotive-section-type="header"><span id="page-header-section"></span>Here some this should not be rendered in middleware</div>)]
      ]
    end

  end

  context "the content of the section is in the request body" do
    let(:body) do
      %({ "section_content": { "id": "dropzone-42", "settings": { "name": "modified HTML" } } })
    end

    it 'renders the HTML code related to the section' do
      is_expected.to eq [
        200,
        { "content-type" => "text/html" },
        [%(<div id="locomotive-section-dropzone-42" class="locomotive-section" data-locomotive-section-type="header"><span id="dropzone-42-section"></span>Here some modified HTML</div>)]
      ]
    end

  end

end
