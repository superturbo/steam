require File.dirname(__FILE__) + '/../integration_helper'

describe 'Page cache' do

  include Rack::Test::Methods

  let(:store) { ActiveSupport::Cache::MemoryStore.new }

  def app
    run_server
  end

  before do
    shared_store = store
    allow(Locomotive::Steam.configuration).to receive(:services_hook).and_return(->(services) { services.cache = shared_store })
    allow_any_instance_of(Locomotive::Steam::Site).to receive(:cache_enabled).and_return(true)
    allow(store).to receive(:write).and_call_original
    allow(store).to receive(:read).and_call_original
  end

  def csrf_token
    last_response.body[/name="authenticity_token" value="([^"]+)"/, 1] || last_response.body[/_csrf[^>]*value="([^"]+)"/, 1]
  end

  it 'shares the page of an anonymous visitor under lowercase cache headers' do
    get '/about-us'
    get '/about-us'

    expect(last_response.status).to eq 200
    expect(last_response.headers.to_h.slice('cache-control', 'vary')).to eq(
      'cache-control' => 'max-age=0, s-maxage=3600, public, must-revalidate', 'vary' => 'Accept-Language')
    expect(last_response.headers.to_h.keys).to include('etag')
    expect(last_response.headers.to_h.keys).not_to include('last-modified')
    expect(store).to have_received(:write).once
  end

  it 'answers If-Modified-Since with the page, even for a site without a modification date' do
    get '/about-us', {}, 'HTTP_IF_MODIFIED_SINCE' => Time.utc(2030, 1, 1).httpdate

    expect(last_response.status).to eq 200
  end

  it "serves a visitor the page their session calls for, not another visitor's copy" do
    get '/contest'
    expect(last_response.body).to include 'Your code is'

    get '/contest'
    expect(last_response.body).to include 'already participated'
    expect(store).not_to have_received(:write)
  end

  it 'keeps a page with a form token to the visitor it was rendered for' do
    get '/events'
    first_token = csrf_token
    clear_cookies

    get '/events'

    expect(first_token).to be_present
    expect(csrf_token).to be_present
    expect(csrf_token).not_to eq first_token
    expect(store).not_to have_received(:write)
  end

  it 'serves a visitor with a session a page of their own, not the shared copy' do
    get '/about-us'
    expect(store).to have_received(:write).once

    get '/contest'
    expect(store).to have_received(:read).twice

    get '/about-us'

    expect(last_response.status).to eq 200
    expect(last_response.headers['cache-control']).to eq 'max-age=0, private, must-revalidate'
    expect(last_response.headers.to_h.keys).not_to include('etag', 'vary')
    expect(store).to have_received(:read).twice
  end

  it 'answers a visitor with a session with their page, even for the current ETag' do
    get '/about-us'
    etag = last_response.headers['etag']

    get '/contest'
    get '/about-us', {}, 'HTTP_IF_NONE_MATCH' => etag

    expect(last_response.status).to eq 200
  end

end
