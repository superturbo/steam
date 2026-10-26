require File.dirname(__FILE__) + '/../integration_helper'

describe 'Section preview' do

  include Rack::Test::Methods

  def app
    run_server
  end

  let(:liquid_in_type) { "header' %}{{ 6 | times: 7 }}{% section 'header" }

  it 'leaves a request outside live editing to the page' do
    get '/index'
    page = last_response.body

    ['header', liquid_in_type].each do |type|
      get '/index', {}, 'HTTP_LOCOMOTIVE_SECTION_TYPE' => type

      expect(last_response.status).to eq 200
      expect(last_response.body).to eq page
    end
  end

  describe 'with the page cache on' do

    let(:store) { ActiveSupport::Cache::MemoryStore.new }

    before do
      shared_store = store
      allow(Locomotive::Steam.configuration).to receive(:services_hook).and_return(->(services) { services.cache = shared_store })
      allow_any_instance_of(Locomotive::Steam::Site).to receive(:cache_enabled).and_return(true)
      set_cookie 'steam-locale=en'
    end

    it 'stores the page, not the section a header asks for' do
      get '/about-us', {}, 'HTTP_CACHE_CONTROL' => 'no-store'
      page = last_response.body

      # An empty body, as Puma gives every request.
      get '/about-us', {}, 'HTTP_LOCOMOTIVE_SECTION_TYPE' => 'header', input: ''.dup
      get '/about-us'

      expect(last_response.headers['age']).to be_present
      expect(last_response.body).to eq page
    end

  end

  describe 'while live editing' do

    let(:live_editing) { { 'steam.live_editing' => true } }

    it 'renders an existing section' do
      put '/index', {}, live_editing.merge('HTTP_LOCOMOTIVE_SECTION_TYPE' => 'header')

      expect(last_response.status).to eq 200
      expect(last_response.body).to include('data-locomotive-section-type="header"')
    end

    it 'refuses a type no section has, without reading it as Liquid' do
      put '/index', {}, live_editing.merge('HTTP_LOCOMOTIVE_SECTION_TYPE' => liquid_in_type)

      expect(last_response.status).to eq 404
      expect(last_response.body).not_to include('42')
    end

  end

end
