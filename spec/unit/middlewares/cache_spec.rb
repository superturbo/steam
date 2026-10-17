require 'spec_helper'

require_relative '../../../lib/locomotive/steam/middlewares/thread_safe'
require_relative '../../../lib/locomotive/steam/middlewares/concerns/helpers'
require_relative '../../../lib/locomotive/steam/middlewares/cache'

describe Locomotive::Steam::Middlewares::Cache do

  let(:now)             { DateTime.parse('2015/09/26 22:00:00') }
  let(:method)          { 'GET' }
  let(:code)            { 200 }
  let(:live_editing)    { nil }
  let(:published)       { true }
  let(:etag)            { nil }
  let(:modified_at)     { nil }
  let(:url)             { 'http://models.example.com' }
  let(:path)            { 'hello-world' }
  let(:page)            { instance_double('Page') }
  let(:cache)           { ActiveSupport::Cache::MemoryStore.new }
  let(:session)         { nil }
  let(:app)             { ->(env) { [code, steam_headers(env), ['Hello world!']] } }
  let(:middleware)      { described_class.new(app) }

  subject do
    env = send_request[:env]
    [env['steam.cache_control'], env['steam.cache_vary']]
  end

  describe 'caching is disabled for the site' do

    let(:site) { instance_double('Site', cache_enabled: false) }

    it 'tells the CDN to not cache the page' do
      is_expected.to eq ['max-age=0, private, must-revalidate', nil]
    end

  end

  describe 'caching is disabled for the site and the render writes to the session' do

    let(:site)    { instance_double('Site', cache_enabled: false) }
    let(:session) { {} }
    let(:app)     { ->(env) { env['rack.session']['csrf.token'] = 't'; [200, { 'cache-control' => 'public, max-age=600' }, ['t']] } }

    it 'keeps the response private' do
      expect(send_request[:headers]['cache-control']).to eq 'max-age=0, private, must-revalidate'
    end

  end

  describe 'caching is disabled for the site and the render sets a cookie' do

    let(:site) { instance_double('Site', cache_enabled: false) }
    let(:app)  { ->(env) { [200, { 'cache-control' => 'public, max-age=600', 'set-cookie' => 'cart=1' }, ['page']] } }

    it 'keeps the response private' do
      expect(send_request[:headers]).to eq('cache-control' => 'max-age=0, private, must-revalidate', 'set-cookie' => 'cart=1')
    end

  end

  describe 'caching is disabled for a page configured no-store' do

    let(:site) { instance_double('Site', cache_enabled: true, cache_control: nil) }
    let(:page) { instance_double('Page', cache_enabled: false, cache_control: 'no-store') }

    it 'keeps no-store' do
      is_expected.to eq ['no-store', nil]
    end

  end

  describe 'caching is disabled for the page' do

    let(:site) { instance_double('Site', cache_enabled: true) }
    let(:page) { instance_double('Page', cache_enabled: false) }

    it 'tells the CDN to not cache the page' do
      is_expected.to eq ['max-age=0, private, must-revalidate', nil]
    end

  end

  describe 'the caching is enabled for the page' do

    let(:site) { instance_double('Site', _id: 42, last_modified_at: now, cache_enabled: true, cache_control: '', cache_vary: nil) }
    let(:page) { instance_double('Page', cache_enabled: true) }

    # A stored page's age counts from the time it was stored.
    around { |example| Timecop.freeze { example.run } }

    # These specs run without a deployment generation.
    around do |example|
      previous = ENV.to_h.slice('RAILS_CACHE_ID', 'RAILS_APP_VERSION')
      ENV.delete('RAILS_CACHE_ID')
      ENV.delete('RAILS_APP_VERSION')
      example.run
    ensure
      ENV.delete('RAILS_CACHE_ID')
      ENV.delete('RAILS_APP_VERSION')
      ENV.update(previous)
    end

    # the key and version Cache#cache_key and #cache_version give this request
    let(:cache_key)     { "steam/page/#{Digest::SHA256.hexdigest("42\nhttp://models.example.com/")}" }
    let(:cache_version) { "#{Locomotive::Steam::VERSION}/#{now.strftime('%s.%N')}" }

    # Keep a page under this request's key and version, with the time it was stored.
    def store(response, version: cache_version, stored_at: Time.now.to_i)
      cache.write(cache_key, Marshal.dump(response + [stored_at]), version: version)
    end

    # Read with read_multi, so it never counts as the request's own read.
    def stored_page
      marshaled = cache.read_multi(cache_key, version: cache_version)[cache_key]
      Marshal.load(marshaled).first(3) if marshaled
    end

    def reads_the_store
      expect(cache).to receive(:read).with(cache_key, hash_including(version: cache_version)).once.and_call_original
    end

    describe 'the key and version the store is read with' do

      def read_by(env = {})
        read = nil
        allow(cache).to receive(:read).and_wrap_original { |original, key, options| read = [key, options[:version]]; original.call(key, options) }
        send_request(env)
        read
      end

      def site_changed_at(time)
        instance_double('Site', _id: 42, last_modified_at: time, cache_enabled: true, cache_control: '', cache_vary: nil)
      end

      it 'keeps a stable key under steam/page/' do
        expect(read_by.first).to eq cache_key
        expect(read_by('steam.site' => site_changed_at(now + 1.day)).first).to eq cache_key
      end

      it 'changes the version for a site change within the same second' do
        expect(read_by('steam.site' => site_changed_at(now + 0.001.seconds)).last).not_to eq read_by.last
      end

      it 'gives one version for one moment in any time type or zone' do
        moment   = now.to_time.utc
        versions = [moment, moment.getlocal('+03:00'), moment.in_time_zone('Vilnius'), moment.to_datetime].map do |time|
          read_by('steam.site' => site_changed_at(time)).last
        end

        expect(versions.uniq).to eq [cache_version]
      end

      it 'gives a site without a modification date a version all the same' do
        expect(read_by('steam.site' => site_changed_at(nil)).last).to eq "#{Locomotive::Steam::VERSION}/none"
      end

      it 'tells apart the same path under another mount point' do
        expect(read_by('SCRIPT_NAME' => '/locomotive/acme/preview').first).not_to eq cache_key
      end

      it 'tells apart the same path with another query' do
        expect(read_by('QUERY_STRING' => 'page=2').first).not_to eq cache_key
      end

      it 'tells apart the same path over another scheme' do
        expect(read_by('rack.url_scheme' => 'https', 'HTTPS' => 'on').first).not_to eq cache_key
      end

      it 'tells apart the same path on another host or port' do
        expect(read_by('HTTP_HOST' => 'sample.example.com').first).not_to eq cache_key
        expect(read_by('HTTP_HOST' => 'models.example.com:8080').first).not_to eq cache_key
      end

      it 'is the same for GET and HEAD' do
        expect(read_by(method: 'HEAD')).to eq read_by
      end

    end

    describe 'under a deployment generation (RAILS_APP_VERSION)' do

      around do |example|
        previous, ENV['RAILS_APP_VERSION'] = ENV['RAILS_APP_VERSION'], 'rollout-42'
        example.run
      ensure
        ENV['RAILS_APP_VERSION'] = previous
      end

      let(:page_etag) { %(W/"#{Digest::SHA256.hexdigest('Hello world!')[0, 32]}") }

      it 'puts the generation first in the version' do
        version = nil
        allow(cache).to receive(:read).and_wrap_original { |original, key, options| version = options[:version]; original.call(key, options) }

        send_request

        expect(version).to eq "rollout-42/#{cache_version}"
      end

      it 'does not serve a page an earlier generation stored' do
        store([200, {}, ['old page']], version: "rollout-41/#{cache_version}")
        expect(send_request[:headers]['etag']).to eq page_etag
      end

      it 'serves a page the same generation stored' do
        store([200, { 'etag' => 'W/"same"' }, ['page']], version: "rollout-42/#{cache_version}")
        expect(send_request[:headers]['etag']).to eq 'W/"same"'
      end

    end

    describe 'the lifetime of a stored page' do

      it 'is the s-maxage of the policy' do
        send_request

        Timecop.travel(Time.now + 3590) { expect(stored_page).not_to be_nil }
        Timecop.travel(Time.now + 3610) { expect(stored_page).to be_nil }
      end

      context 'once it ends' do

        let(:renders) { [] }
        let(:app)     { ->(env) { renders << env['PATH_INFO']; [200, steam_headers(env), ['page']] } }

        it 'has the next request render the page again' do
          2.times { send_request }
          expect(renders.size).to eq 1

          Timecop.travel(Time.now + 3610) { send_request }
          expect(renders.size).to eq 2
        end

      end

      context 'when the render answers a shorter s-maxage' do

        let(:app) { ->(env) { [200, steam_headers(env).merge('cache-control' => 'public, s-maxage=30'), ['page']] } }

        it 'is that s-maxage' do
          send_request

          Timecop.travel(Time.now + 20) { expect(stored_page).not_to be_nil }
          Timecop.travel(Time.now + 40) { expect(stored_page).to be_nil }
        end

      end

      context 'under a policy that repeats the same s-maxage' do

        let(:site) { instance_double('Site', _id: 42, last_modified_at: now, cache_enabled: true, cache_control: 'public, s-maxage=60, s-maxage=60', cache_vary: nil) }

        it 'is that s-maxage' do
          send_request

          Timecop.travel(Time.now + 50) { expect(stored_page).not_to be_nil }
          Timecop.travel(Time.now + 70) { expect(stored_page).to be_nil }
        end

      end

      context 'under a policy with a max-age only' do

        let(:site) { instance_double('Site', _id: 42, last_modified_at: now, cache_enabled: true, cache_control: 'public, max-age=600', cache_vary: nil) }

        it 'is the max-age' do
          send_request

          Timecop.travel(Time.now + 590) { expect(stored_page).not_to be_nil }
          Timecop.travel(Time.now + 610) { expect(stored_page).to be_nil }
        end

      end

    end

    describe 'a policy that gives Steam no lifetime, or asks for a validation Steam does not do' do

      before do
        expect(cache).not_to receive(:read)
        expect(cache).not_to receive(:write)
      end

      ['public', 'public, s-maxage=0', 'max-age=0, public', 'public, s-maxage=soon', 'public, s-maxage=60, s-maxage=30',
       'public, s-maxage=60s', 'public, s-maxage="60"', 'public, s-maxage, max-age=600', 'public, s-maxage=60, s-maxage', 'public, s-maxage=60, no-cache', 'public, s-maxage=60, No-Cache="set-cookie"'].each do |policy|

        context "(#{policy})" do

          let(:site) { instance_double('Site', _id: 42, last_modified_at: now, cache_enabled: true, cache_control: policy, cache_vary: nil) }

          it 'renders the page and keeps nothing' do
            expect(send_request[:code]).to eq 200
          end

        end

      end

    end

    describe "a request's own Cache-Control" do

      it 'keeps the response to a request asking for No-Store out of the store' do
        response = send_request('HTTP_CACHE_CONTROL' => 'No-Store')

        expect(response[:code]).to eq 200
        expect(response[:env]['steam.cache_control']).to eq 'max-age=0, s-maxage=3600, public, must-revalidate'
        expect(stored_page).to be_nil
      end

      it 'still answers such a request from a page already stored' do
        store([200, { 'cache-control' => 'max-age=0, s-maxage=3600, public, must-revalidate', 'etag' => 'W/"stored"' }, ['page']])
        expect(send_request('HTTP_CACHE_CONTROL' => 'no-store')[:headers]['etag']).to eq 'W/"stored"'
      end

      it 'answers a request asking for no-cache from the store all the same' do
        store([200, { 'cache-control' => 'max-age=0, s-maxage=3600, public, must-revalidate', 'etag' => 'W/"stored"' }, ['page']])
        expect(send_request('HTTP_CACHE_CONTROL' => 'no-cache')[:headers]['etag']).to eq 'W/"stored"'
      end

    end

    describe 'the age of a stored page' do

      it 'is sent on a hit, in seconds since the page was stored' do
        send_request
        Timecop.freeze(Time.now + 100) { expect(send_request[:headers]['age']).to eq '100' }
      end

      it 'is sent with a 304 answered from the stored copy' do
        page_etag = send_request[:headers]['etag']
        Timecop.freeze(Time.now + 100) do
          response = send_request('HTTP_IF_NONE_MATCH' => page_etag)
          expect([response[:code], response[:headers]['age']]).to eq [304, '100']
        end
      end

      it 'is never negative, though another server with its clock ahead stored the page' do
        store([200, { 'cache-control' => 'max-age=0, s-maxage=3600, public, must-revalidate' }, ['page']], stored_at: Time.now.to_i + 30)
        expect(send_request[:headers]['age']).to eq '0'
      end

      it 'is sent on a HEAD hit as well' do
        send_request
        Timecop.freeze(Time.now + 100) { expect(send_request(method: 'HEAD')[:headers]['age']).to eq '100' }
      end

      context 'when the render answers with an Age of its own, as a copy from another cache' do

        let(:app) { ->(env) { [200, steam_headers(env).merge('age' => '3500'), ['page']] } }

        it 'is passed on, and the page is not stored' do
          expect(send_request[:headers]['age']).to eq '3500'
          expect(stored_page).to be_nil
        end

      end

      it 'is not sent with a page rendered for the request' do
        expect(send_request[:headers]).not_to have_key('age')
      end

      it 'is not stored with the page' do
        send_request
        Timecop.freeze(Time.now + 100) { send_request }
        expect(stored_page[1]).not_to have_key('age')
      end

      it 'cannot be told for a copy stored without its time, which is rendered again' do
        cache.write(cache_key, Marshal.dump([200, {}, ['old page']]), version: cache_version)
        expect(send_request[:headers]['etag']).to eq %(W/"#{Digest::SHA256.hexdigest('Hello world!')[0, 32]}")
      end

    end

    describe 'a page Steam stores' do

      it 'is kept under this version only' do
        send_request

        expect(stored_page).not_to be_nil
        expect(cache.read_multi(cache_key, version: 'another version')).to be_empty
      end

    end

    describe 'a copy stored under another version' do

      before { store([200, {}, ['old page']], version: 'another version') }

      it 'is not served: the page is rendered and stored under this version' do
        expect(send_request[:headers]['etag']).to eq %(W/"#{Digest::SHA256.hexdigest('Hello world!')[0, 32]}")
        expect(stored_page.last).to eq ['Hello world!']
      end

    end

    describe 'a store that is not an ActiveSupport::Cache::Store' do

      let(:cache) { double('CustomStore') }

      it 'is neither read nor written, and a warning says so once' do
        expect(Locomotive::Common::Logger).to receive(:warn).with(/not an ActiveSupport::Cache::Store/).once

        2.times do
          response = send_request
          expect(response[:code]).to eq 200
          expect(response[:env]['steam.cache_control']).to eq 'max-age=0, s-maxage=3600, public, must-revalidate'
        end
      end

    end

    describe 'the ETag of a page rendered for the store' do

      let(:rendered)     { 'Hello world!' }
      let(:app)          { ->(env) { [code, steam_headers(env), [rendered]] } }
      let(:content_etag) { %(W/"#{Digest::SHA256.hexdigest(rendered)[0, 32]}") }

      it 'digests the rendered page, as Rack::ETag does, and is stored with it' do
        expect(send_request[:headers]['etag']).to eq content_etag
        expect(stored_page).to eq [200, stored_headers_for(rendered), [rendered]]
      end

      context 'rendered three times under the same key, the second time differently' do

        let(:renders) { ['Hello world!', 'Hello again!', 'Hello world!'] }
        let(:app)     { ->(env) { [200, steam_headers(env), [renders.shift]] } }

        it 'changes with the page, not with the key' do
          etags = Array.new(3) { cache.clear; send_request[:headers]['etag'] }

          expect(etags[1]).not_to eq etags[0]
          expect(etags[2]).to eq etags[0]
        end

      end

      context 'when the render sets an ETag of its own' do

        let(:app) { ->(env) { [200, steam_headers(env).merge('etag' => '"own"'), [rendered]] } }

        it 'keeps it' do
          expect(send_request[:headers]['etag']).to eq '"own"'
        end

      end

      context 'when the page is empty' do

        let(:app) { ->(env) { [200, steam_headers(env), ['']] } }

        it 'adds none' do
          expect(send_request[:headers]).not_to have_key('etag')
        end

      end

      context 'for a HEAD request' do

        let(:method) { 'HEAD' }

        it 'adds none, since the GET page is not known and a template can render HEAD differently' do
          expect(send_request[:headers]).not_to have_key('etag')
        end

      end

    end

    context 'the request is a GET' do

      let(:response) { nil }

      before do
        store(response) if response
        reads_the_store
      end

      context 'the cache is empty' do

        after { expect(stored_page.last).to eq ['Hello world!'] }

        it 'tells the CDN to cache the page and also cache it internally' do
          is_expected.to eq ['max-age=0, s-maxage=3600, public, must-revalidate', 'Accept-Language']
        end

        it 'sends no last modification date' do
          expect(send_request[:env].keys.grep(/last_modified/)).to be_empty
        end

        describe 'the site administrator sets a custom cache control and vary' do

          let(:site) { instance_double('Site', _id: 42, last_modified_at: now, cache_enabled: true, cache_control: 'max-age=600, s-maxage=600, public, must-revalidate', cache_vary: 'accept-language') }

          it 'tells the CDN to cache the page with the custom cache control' do
            is_expected.to eq ['max-age=600, s-maxage=600, public, must-revalidate', 'accept-language']
          end

        end

      end

      describe 'the cache contains the response' do

        let(:response) { [200, {}, ["Hello world!"]] }

        it 'tells the CDN to cache the page' do
          expect(cache).not_to receive(:write)
          is_expected.to eq ['max-age=0, s-maxage=3600, public, must-revalidate', 'Accept-Language']
        end

      end

    end

    describe 'the page has not been modified for a while' do

      subject { [send_request[:code], send_request[:headers]] }

      let(:stored_etag)    { %(W/"#{cache_key}") }
      let(:stored_code)    { 200 }
      let(:stored_headers) do
        { 'cache-control' => 'max-age=0, s-maxage=3600, public, must-revalidate', 'vary' => 'Accept-Language', 'etag' => stored_etag,
          'expires' => 'Sat, 26 Sep 2015 23:00:00 GMT', 'content-location' => '/hello-world', 'date' => now.httpdate }
      end

      context 'with a stored copy' do

        before do
          store([stored_code, { 'content-type' => 'text/html', 'x-own' => '1' }.merge(stored_headers), ['Hello world!']])
        end

        {
          'its ETag'                       => ->(tag) { tag },
          'its ETag without W/'            => ->(tag) { tag.delete_prefix('W/') },
          'its ETag among others'          => ->(tag) { %("other", W/"x", #{tag}) },
          'its ETag among empty items'     => ->(tag) { %(, #{tag} ,) },
          'any ETag'                       => ->(_)   { '*' },
          'any ETag, padded'               => ->(_)   { ' * ' }
        }.each do |name, if_none_match|

          context "and a request naming #{name}" do

            let(:etag) { if_none_match.call(stored_etag) }

            it 'answers 304 with the validator and policy the stored copy carries, and its age' do
              expect(subject).to eq [304, stored_headers.merge('age' => '0')]
            end

          end

        end

        {
          'another ETag'                   => ->(_)   { '"other"' },
          'its ETag without quotes'        => ->(tag) { tag.delete_prefix('W/').delete('"') },
          'its ETag inside other text'     => ->(tag) { %(garbage#{tag.delete_prefix('W/')}) },
          'its ETag after an invalid item' => ->(tag) { %(garbage"other", #{tag}) },
          'any ETag among others'          => ->(_)   { '*, "other"' }
        }.each do |name, if_none_match|

          context "and a request naming #{name}" do

            let(:etag) { if_none_match.call(stored_etag) }

            it 'serves the stored copy' do
              expect(subject.first).to eq 200
            end

          end

        end

        context 'whose ETag holds a comma and a request naming it' do

          let(:stored_etag) { 'W/"a,b"' }
          let(:etag)        { stored_etag }

          it 'serves the stored copy, since such tags are not supported' do
            expect(subject.first).to eq 200
          end

        end

        context 'that is not a 200 and a request naming its ETag' do

          let(:stored_code) { 404 }
          let(:etag)        { stored_etag }

          it 'serves the stored copy' do
            expect(subject.first).to eq 404
          end

        end

      end

      context 'without a stored copy' do

        {
          'the current ETag' => ->(tag) { tag },
          'any ETag'         => ->(_)   { '*' }
        }.each do |name, if_none_match|

          context "and a request naming #{name}" do

            let(:etag) { if_none_match.call(stored_etag) }

            it 'renders the page, since no shared copy proves it' do
              expect(subject.first).to eq 200
            end

          end

        end

      end

      context 'based on If-Modified-Since alone' do

        let(:modified_at) { now.httpdate }

        before { store([200, {}, ['Hello world!']]) }

        it 'serves the page, since the site date does not follow a Steam upgrade' do
          expect(subject.first).to eq 200
        end

      end

    end

    context 'a visitor with a session' do

      let(:session) { { 'authenticated_entry_id' => '42' } }
      let(:etag)    { %(W/"#{cache_key}") }

      it 'neither reads nor writes the shared copy and keeps the page private' do
        response = send_request

        expect(response[:code]).to eq 200
        expect([response[:env]['steam.cache_control'], response[:env]['steam.cache_vary']]).to eq ['max-age=0, private, must-revalidate', nil]
        expect(response[:headers]).not_to have_key('etag')
      end

    end

    context 'a visitor with a session on a page configured No-Store' do

      let(:page)    { instance_double('Page', cache_enabled: true, cache_control: 'No-Store', cache_vary: nil) }
      let(:session) { { 'authenticated_entry_id' => '42' } }

      it 'keeps no-store, which is stricter than private, whatever its case' do
        expect(send_request[:env]['steam.cache_control']).to eq 'no-store'
      end

    end

    context 'a visitor with a session on a site configured with another directive holding no-store' do

      let(:site)    { instance_double('Site', _id: 42, last_modified_at: now, cache_enabled: true, cache_control: 'x-no-store, public', cache_vary: nil) }
      let(:session) { { 'authenticated_entry_id' => '42' } }

      it 'keeps the response private only' do
        expect(send_request[:env]['steam.cache_control']).to eq 'max-age=0, private, must-revalidate'
      end

    end

    context 'a render that writes to the session on a site configured no-store' do

      let(:site)    { instance_double('Site', _id: 42, last_modified_at: now, cache_enabled: true, cache_control: 'no-store', cache_vary: nil) }
      let(:session) { {} }
      let(:app)     { ->(env) { env['rack.session']['csrf.token'] = 't'; [200, { 'cache-control' => env['steam.cache_control'] }, ['t']] } }

      before { expect(cache).not_to receive(:read) }

      it 'keeps no-store, which is stricter than private' do
        expect(cache).not_to receive(:write)
        expect(send_request[:headers]['cache-control']).to eq 'no-store'
      end

    end

    context 'a visitor with a session on a site configured no-store with another directive' do

      let(:site)    { instance_double('Site', _id: 42, last_modified_at: now, cache_enabled: true, cache_control: 'no-store, no-transform', cache_vary: nil) }
      let(:session) { { 'authenticated_entry_id' => '42' } }

      it 'keeps no-store and no-transform' do
        expect(send_request[:env]['steam.cache_control']).to eq 'no-store, no-transform'
      end

    end

    context 'a visitor with a session on a site configured for public caching with no-transform' do

      let(:site)    { instance_double('Site', _id: 42, last_modified_at: now, cache_enabled: true, cache_control: 'public, s-maxage=600, no-transform', cache_vary: nil) }
      let(:session) { { 'authenticated_entry_id' => '42' } }

      it 'keeps no-transform only' do
        expect(send_request[:env]['steam.cache_control']).to eq 'max-age=0, private, must-revalidate, no-transform'
      end

    end

    context 'a visitor with a session on a site whose no-cache argument quotes no-store' do

      let(:site)    { instance_double('Site', _id: 42, last_modified_at: now, cache_enabled: true, cache_control: 'no-cache="set-cookie,no-store,x"', cache_vary: nil) }
      let(:session) { { 'authenticated_entry_id' => '42' } }

      it 'reads no no-store directive' do
        expect(send_request[:env]['steam.cache_control']).to eq 'max-age=0, private, must-revalidate'
      end

    end

    context 'a visitor whose session the render clears before answering for public caching' do

      let(:session) { { 'authenticated_entry_id' => '42' } }
      let(:app)     { ->(env) { env['rack.session'].clear; [200, { 'cache-control' => 'public, max-age=600' }, ['page']] } }

      it 'keeps the response private, since it was rendered for that session' do
        expect(send_request[:headers]['cache-control']).to eq 'max-age=0, private, must-revalidate'
      end

    end

    context 'a visitor with a session whose response sets cache-control of its own' do

      let(:session) { { 'authenticated_entry_id' => '42' } }
      let(:app)     { ->(env) { [200, { 'cache-control' => 'public, max-age=600' }, ['page']] } }

      it 'keeps the response private' do
        expect(send_request[:headers]['cache-control']).to eq 'max-age=0, private, must-revalidate'
      end

    end

    context 'a render that writes to the session and answers no-store itself' do

      let(:session) { {} }
      let(:app)     { ->(env) { env['rack.session']['csrf.token'] = 't'; [200, { 'cache-control' => 'private, No-Store' }, ['t']] } }

      before { reads_the_store }

      it 'keeps no-store' do
        expect(cache).not_to receive(:write)
        expect(send_request[:headers]['cache-control']).to eq 'no-store'
      end

    end

    context 'a render that writes to the session and sets headers of its own' do

      let(:session) { {} }
      let(:app)     { ->(env) { env['rack.session']['csrf.token'] = 't'; [200, { 'etag' => 'W/"own"', 'vary' => 'Cookie', 'x-own' => '1' }, ['t']] } }

      before { reads_the_store }

      it 'keeps an etag and vary other than the ones Steam set for the shared copy' do
        expect(cache).not_to receive(:write)
        expect(send_request[:headers]).to eq('cache-control' => 'max-age=0, private, must-revalidate', 'etag' => 'W/"own"',
                                             'vary' => 'Cookie', 'x-own' => '1')
      end

    end

    context 'a render that writes to the session' do

      let(:session) { {} }
      let(:app) do
        ->(env) do
          env['rack.session']['csrf.token'] = 'visitor token'
          headers = { 'cache-control' => env['steam.cache_control'], 'vary' => env['steam.cache_vary'] }
          [200, headers, ['visitor token']]
        end
      end

      before { reads_the_store }

      it 'serves the page to this visitor only' do
        expect(cache).not_to receive(:write)

        response = send_request

        expect(response[:headers]).to eq('cache-control' => 'max-age=0, private, must-revalidate')
        expect(response[:env]['steam.cache_control']).to eq 'max-age=0, private, must-revalidate'
      end

    end

    context 'a HEAD request that finds no stored copy' do

      let(:method) { 'HEAD' }

      before { reads_the_store }

      it 'keeps the public headers but stores nothing, since a template can render HEAD differently' do
        expect(cache).not_to receive(:write)
        is_expected.to eq ['max-age=0, s-maxage=3600, public, must-revalidate', 'Accept-Language']
      end

    end

    describe 'a policy that keeps the page out of a shared cache' do

      subject { send_request }

      before do
        expect(cache).not_to receive(:read)
        expect(cache).not_to receive(:write)
      end

      {
        'the site answering no-store'          => [{ cache_control: 'no-store' }, {}],
        'the page answering Private, max-age=600' => [{ cache_control: '' }, { cache_control: 'Private, max-age=600' }]
      }.each do |name, (site_policy, page_policy)|

        context name do

          let(:site) { instance_double('Site', _id: 42, last_modified_at: now, cache_enabled: true, cache_vary: nil, **site_policy) }
          let(:page) { instance_double('Page', cache_enabled: true, cache_vary: nil, **{ cache_control: nil }.merge(page_policy)) }

          it 'renders the page and sends the policy as configured' do
            response = subject
            expect(response[:code]).to eq 200
            expect(response[:env]['steam.cache_control']).to eq((page_policy[:cache_control] || site_policy[:cache_control]))
          end

        end

      end

    end

    describe 'a page that varies on a request header its render may depend on' do

      before do
        expect(cache).not_to receive(:read)
        expect(cache).not_to receive(:write)
      end

      ['User-Agent', 'Accept-Language, user-agent', 'Accept-Encoding', '*'].each do |vary|

        context "(Vary: #{vary})" do

          let(:site) { instance_double('Site', _id: 42, last_modified_at: now, cache_enabled: true, cache_control: '', cache_vary: vary) }

          it 'renders the page for each request and keeps the public policy for a CDN that varies on it' do
            response = send_request
            expect(response[:code]).to eq 200
            expect([response[:env]['steam.cache_control'], response[:env]['steam.cache_vary']]).to eq ['max-age=0, s-maxage=3600, public, must-revalidate', vary]
          end

        end

      end

      context 'and whose render fails' do

        let(:site) { instance_double('Site', _id: 42, last_modified_at: now, cache_enabled: true, cache_control: '', cache_vary: 'User-Agent') }
        let(:app)  { ->(env) { [500, { 'cache-control' => env['steam.cache_control'], 'vary' => env['steam.cache_vary'] }, ['error']] } }

        it 'keeps the error private' do
          expect(send_request[:headers]).to eq('cache-control' => 'max-age=0, private, must-revalidate')
        end

      end

    end

    describe 'a render that answers with a policy of its own' do

      before { reads_the_store }

      {
        'private'                 => { 'cache-control' => 'private, max-age=60' },
        'no-store'                => { 'cache-control' => 'No-Store' },
        'varying on User-Agent'   => { 'cache-control' => 'max-age=0, s-maxage=3600, public, must-revalidate', 'vary' => 'User-Agent' },
        'with no lifetime'        => { 'cache-control' => 'public' },
        'with s-maxage=0'         => { 'cache-control' => 'public, s-maxage=0' },
        'with no-cache'           => { 'cache-control' => 'public, s-maxage=3600, no-cache' }
      }.each do |name, headers|

        context "(#{name})" do

          let(:app) { ->(env) { [200, headers.dup, ['page']] } }

          it 'is not stored, though the configured policy is public' do
            expect(cache).not_to receive(:write)
            expect(send_request[:code]).to eq 200
          end

        end

      end

    end

    context 'a visitor Steam prepared a cookie for before the page cache' do

      it 'neither reads nor writes the shared copy and keeps the page private' do
        expect(cache).not_to receive(:read)
        expect(cache).not_to receive(:write)

        response = send_request('steam.cookies' => { 'steam-locale' => { 'value' => 'en' } })

        expect([response[:env]['steam.cache_control'], response[:env]['steam.cache_vary']]).to eq ['max-age=0, private, must-revalidate', nil]
      end

    end

    context 'a render that sets a cookie' do

      let(:app) { ->(env) { [200, { 'cache-control' => env['steam.cache_control'], 'vary' => env['steam.cache_vary'], 'set-cookie' => 'cart=1' }, ['page']] } }

      before { reads_the_store }

      it 'serves the page to this visitor only' do
        expect(cache).not_to receive(:write)
        expect(send_request[:headers]).to eq('cache-control' => 'max-age=0, private, must-revalidate', 'set-cookie' => 'cart=1')
      end

    end

    context 'a render that prepares a cookie' do

      let(:app) { ->(env) { env['steam.cookies'] = { 'cart' => { 'value' => '1' } }; [200, {}, ['page']] } }

      before { reads_the_store }

      it 'stores nothing and keeps the page private' do
        expect(cache).not_to receive(:write)
        expect(send_request[:headers]['cache-control']).to eq 'max-age=0, private, must-revalidate'
      end

    end

    context 'a copy stored with a Set-Cookie, by an earlier Steam' do

      before { store([200, { 'set-cookie' => 'visitor=first' }, ['old page']]) }

      it 'is not served: the page is rendered and stored again' do
        expect(send_request[:headers]).not_to have_key('set-cookie')
        expect(stored_page).to eq [200, stored_headers_for('Hello world!'), ['Hello world!']]
      end

    end

    context 'a render that leaves the session empty' do

      let(:session) { {} }

      before { reads_the_store }
      after  { expect(stored_page).to eq [200, stored_headers_for('Hello world!'), ['Hello world!']] }

      it { is_expected.to eq ['max-age=0, s-maxage=3600, public, must-revalidate', 'Accept-Language'] }

    end

    context 'the request is a POST' do

      let(:method) { 'POST' }

      it 'tells the CDN to not cache the page' do
        is_expected.to eq ['max-age=0, private, must-revalidate', nil]
      end

    end

    context 'the response is a redirection (302)' do

      let(:code) { 302 }

      before { expect(cache).not_to receive(:write) }

      it 'tells the CDN to not cache the page, and stores nothing' do
        is_expected.to eq ['max-age=0, private, must-revalidate', nil]
      end

      it 'sends no vary header at all' do
        expect(send_request[:headers]).to eq('cache-control' => 'max-age=0, private, must-revalidate')
      end

    end

    context 'the live editing mode is on' do

      let(:live_editing) { true }

      it 'tells the CDN to not cache the page' do
        is_expected.to eq ['max-age=0, private, must-revalidate', nil]
      end

    end

    context 'a request Steam must not store, such as a password reset link' do

      it 'neither reads nor writes the store' do
        store([200, stored_headers_for('Stored'), ['Stored']])
        expect(cache).not_to receive(:read)
        expect(cache).not_to receive(:write)

        expect(send_request('steam.no_store' => true)[:headers]).to eq('cache-control' => 'max-age=0, private, must-revalidate')
      end

    end

  end

  # What Steam's renderer answers with (render_response): the policy the cache set.
  def steam_headers(env)
    { 'cache-control' => env['steam.cache_control'], 'vary' => env['steam.cache_vary'] }.compact
  end

  def stored_headers_for(body)
    { 'cache-control' => 'max-age=0, s-maxage=3600, public, must-revalidate', 'vary' => 'Accept-Language',
      'etag' => %(W/"#{Digest::SHA256.hexdigest(body)[0, 32]}") }
  end

  def send_request(overrides = {})
    env = env_for(url, {
      method:                   method,
      'HTTP_IF_NONE_MATCH'      => etag,
      'HTTP_IF_MODIFIED_SINCE'  => modified_at,
      'steam.site'              => site,
      'steam.page'              => page,
      'steam.path'              => path,
      'steam.locale'            => 'en',
      'steam.live_editing'      => live_editing,
      'rack.session'            => session,
      'steam.services'          => instance_double('Services', cache: cache)
    }.merge(overrides))

    env['steam.request'] = Rack::Request.new(env)

    code, headers, body = middleware.call(env)

    { env: env, code: code, headers: headers }
  end

end
