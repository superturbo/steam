require File.dirname(__FILE__) + '/../integration_helper'

describe 'Page cache' do

  include Rack::Test::Methods

  let(:store) { ActiveSupport::Cache::MemoryStore.new }

  let(:not_modified_headers) { %w(cache-control content-location date etag expires vary) }

  def app
    run_server
  end

  before do
    shared_store = store
    allow(Locomotive::Steam.configuration).to receive(:services_hook).and_return(->(services) { services.cache = shared_store })
    allow_any_instance_of(Locomotive::Steam::Site).to receive(:cache_enabled).and_return(true)
    allow(store).to receive(:write).and_call_original
    allow(store).to receive(:read).and_call_original

    # A returning visitor whose locale cookie already holds English.
    set_cookie 'steam-locale=en'
    set_cookie 'steam-locale=en', URI('http://sample.example.com')
  end

  def locale_cookie
    Array(last_response.headers['set-cookie']).flat_map { |header| header.split("\n") }.find { |cookie| cookie.start_with?('steam-locale=') }
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

  it 'answers 304 for the stored copy, repeating the validator and caching headers of its 200' do
    get '/about-us'
    ok = last_response.headers.to_h

    get '/about-us', {}, 'HTTP_IF_NONE_MATCH' => ok['etag']

    expect(ok['etag']).to match(%r{\AW/"\h{32}"\z})
    expect(ok).not_to have_key('date')
    expect(last_response.status).to eq 304
    expect(last_response.headers.to_h).to eq ok.slice(*not_modified_headers)
  end

  it 'answers a HEAD request holding the ETag with the same 304' do
    get '/about-us'
    ok = last_response.headers.to_h

    head '/about-us', {}, 'HTTP_IF_NONE_MATCH' => ok['etag']

    expect(last_response.status).to eq 304
    expect(last_response.headers.to_h).to eq ok.slice(*not_modified_headers)
    expect(last_response.body).to be_empty
  end

  it 'renders the page for the current ETag once the stored copy is gone' do
    get '/about-us'
    etag = last_response.headers['etag']
    store.clear

    get '/about-us', {}, 'HTTP_IF_NONE_MATCH' => etag

    expect(last_response.status).to eq 200
    expect(last_response.body).to include '</html>'
  end

  it 'stores a copy for each scheme and host' do
    get 'http://example.org/about-us'
    get 'https://example.org/about-us'
    get 'http://sample.example.com/about-us'

    expect(store).to have_received(:write).exactly(3).times
  end

  it 'renders a page without a locale in its path in the default locale, whatever language the visitor asks for' do
    get '/about-us'
    get '/about-us', {}, 'HTTP_ACCEPT_LANGUAGE' => 'fr'
    expect(last_response.body).to include 'About us'
    expect(locale_cookie).to be_nil

    set_cookie 'steam-locale=fr'
    get '/about-us'
    expect(last_response.body).to include 'About us'
    expect(locale_cookie).to start_with 'steam-locale=en'

    expect(store).to have_received(:write).once
  end

  it 'stores nothing for the root a visitor is redirected from to their language' do
    clear_cookies
    get '/', {}, 'HTTP_ACCEPT_LANGUAGE' => 'fr'
    expect(last_response.status).to eq 302
    clear_cookies
    set_cookie 'steam-locale=fr'
    get '/'
    expect(last_response.status).to eq 302

    expect(store).not_to have_received(:write)
  end

  describe 'a visitor Steam sets a cookie for' do

    before { clear_cookies }

    it 'gets it on a private page, and the page is shared once their cookie holds the locale' do
      get '/about-us'
      expect(locale_cookie).to start_with 'steam-locale=en'
      expect(last_response.headers['cache-control']).to eq 'max-age=0, private, must-revalidate'
      expect(store).not_to have_received(:write)

      get '/about-us'
      expect(locale_cookie).to be_nil
      expect(last_response.headers['cache-control']).to eq 'max-age=0, s-maxage=3600, public, must-revalidate'
      expect(store).to have_received(:write).once
    end

    it 'gets it with the page, not a 304, even holding the ETag of the shared copy' do
      set_cookie 'steam-locale=en'
      get '/about-us'
      etag = last_response.headers['etag']
      expect(store).to have_received(:write).once

      clear_cookies
      get '/about-us', {}, 'HTTP_IF_NONE_MATCH' => etag

      expect(last_response.status).to eq 200
      expect(locale_cookie).to start_with 'steam-locale=en'
      expect(last_response.headers['cache-control']).to eq 'max-age=0, private, must-revalidate'
    end

    it 'still gets it when a visitor whose cookie holds the locale stored the page first' do
      set_cookie 'steam-locale=fr'
      get '/fr/a-notre-sujet'
      expect(locale_cookie).to be_nil
      expect(store).to have_received(:write).once

      clear_cookies
      get '/fr/a-notre-sujet'
      expect(locale_cookie).to start_with 'steam-locale=fr'
      expect(last_response.headers['cache-control']).to eq 'max-age=0, private, must-revalidate'
      expect(last_response.body).to include 'A notre sujet'
      expect(store).to have_received(:write).once
    end

  end

  it 'keeps a page whose action sets a cookie to the visitor it was rendered for' do
    2.times do
      # Another visitor each time, whose locale cookie already holds English.
      clear_cookies
      set_cookie 'steam-locale=en'
      get '/tags/cookie-action'

      expect(Array(last_response.headers['set-cookie']).join("\n")).to include 'visitor=first'
      expect(last_response.headers['cache-control']).to eq 'max-age=0, private, must-revalidate'
    end

    expect(store).not_to have_received(:write)
  end

  it "keeps pages out of Steam's store under a site policy that forbids a shared cache, and sends that policy" do
    allow_any_instance_of(Locomotive::Steam::Site).to receive(:cache_control).and_return('private, max-age=600')

    2.times { get '/about-us' }

    expect(last_response.headers['cache-control']).to eq 'private, max-age=600'
    expect(store).not_to have_received(:read)
    expect(store).not_to have_received(:write)
  end

  it 'renders a page that varies on User-Agent for each request, and keeps its Vary for a CDN' do
    allow_any_instance_of(Locomotive::Steam::Site).to receive(:cache_vary).and_return('User-Agent')

    get '/about-us', {}, 'HTTP_USER_AGENT' => 'phone'
    get '/about-us', {}, 'HTTP_USER_AGENT' => 'desktop'

    expect(last_response.headers.to_h.slice('cache-control', 'vary')).to eq(
      'cache-control' => 'max-age=0, s-maxage=3600, public, must-revalidate', 'vary' => 'User-Agent')
    expect(store).not_to have_received(:read)
    expect(store).not_to have_received(:write)
  end

  it "lets a host clear Steam's pages alone, in a namespaced store too" do
    Dir.mktmpdir do |dir|
      [ActiveSupport::Cache::MemoryStore.new(namespace: 'app'), ActiveSupport::Cache::FileStore.new(dir, namespace: 'app')].each do |shared_store|
        allow(Locomotive::Steam.configuration).to receive(:services_hook).and_return(->(services) { services.cache = shared_store })
        allow(shared_store).to receive(:write).and_call_original
        shared_store.write('other', 'kept')

        get '/about-us'
        shared_store.delete_matched(%r{^steam/page/})
        get '/about-us'

        expect(shared_store).to have_received(:write).with(start_with('steam/page/'), anything, anything).twice
        expect(shared_store.read('other')).to eq 'kept'
      end
    end
  end

  describe 'without a store, as Wagon and a standalone Steam run' do

    before { allow(Locomotive::Steam.configuration).to receive(:services_hook).and_call_original }

    it 'serves the page on each request instead of failing to store it' do
      2.times do
        get '/about-us'

        expect(last_response.status).to eq 200
        expect(last_response.body).to include 'About us'
      end
    end

  end

  describe 'mounted twice, as the Engine mounts its preview' do

    def app
      steam = run_server
      Rack::Builder.new do
        map('/locomotive/acme/preview') { run steam }
        run steam
      end.to_app
    end

    it 'stores a copy for each mount point' do
      get '/about-us'
      get '/locomotive/acme/preview/about-us'

      expect(last_response.status).to eq 200
      expect(store).to have_received(:write).twice
    end

  end

  describe 'behind the conditional GET middlewares of the Rails default stack' do

    def app
      steam = run_server
      Rack::Builder.new do
        use Rack::Lint
        use Rack::Head
        use Rack::ConditionalGet
        use Rack::ETag, 'no-cache'
        run steam
      end.to_app
    end

    it 'keeps the ETag Steam sends and answers 304 for it, with or without W/' do
      get '/about-us'
      ok   = last_response.headers.to_h
      etag = ok['etag']
      expect(etag).to match(%r{\AW/"\h{32}"\z})

      get '/about-us', {}, 'HTTP_IF_NONE_MATCH' => etag
      expect(last_response.status).to eq 304
      expect(last_response.headers.to_h).to eq ok.slice(*not_modified_headers)

      get '/about-us', {}, 'HTTP_IF_NONE_MATCH' => etag.delete_prefix('W/')
      expect(last_response.status).to eq 304
    end

    it "still sends a visitor's new locale cookie with the 304 Rack::ConditionalGet makes for the same page" do
      get '/about-us'
      etag = last_response.headers['etag']

      clear_cookies
      get '/about-us', {}, 'HTTP_IF_NONE_MATCH' => etag

      expect(last_response.status).to eq 304
      expect(locale_cookie).to start_with 'steam-locale=en'
      expect(last_response.headers['cache-control']).to eq 'max-age=0, private, must-revalidate'
    end

    context 'with an empty store and the same key, as after a deploy' do

      it 'answers an ETag whose page now renders differently with the new page' do
        get '/about-us'
        etag = last_response.headers['etag']
        store.clear
        allow(Locomotive::Steam.configuration).to receive(:asset_host).and_return('https://cdn.example.com')

        get '/about-us', {}, 'HTTP_IF_NONE_MATCH' => etag

        expect(last_response.status).to eq 200
        expect(last_response.body).to include 'https://cdn.example.com/'
        expect(last_response.headers['etag']).not_to eq etag
      end

      it 'answers an ETag whose page renders the same with a 304' do
        get '/about-us'
        etag = last_response.headers['etag']
        store.clear

        get '/about-us', {}, 'HTTP_IF_NONE_MATCH' => etag

        expect(last_response.status).to eq 304
      end

    end

  end

end
