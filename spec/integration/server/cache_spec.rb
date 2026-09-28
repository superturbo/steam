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

end
