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
  let(:cache)           { instance_double('CacheService', ) }
  let(:session)         { nil }
  let(:app)             { ->(env) { [code, {}, ['Hello world!']] } }
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

    # same formula as Cache#cache_key
    let(:cache_key) { Digest::MD5.hexdigest("#{Locomotive::Steam::VERSION}/site/42/#{now.strftime('%s.%N')}/url/http://models.example.com/") }

    describe 'the key' do

      before do
        allow(cache).to receive(:read).and_return(nil)
        allow(cache).to receive(:write)
      end

      def etag_of(env = {})
        send_request(env)[:env]['steam.cache_etag']
      end

      def site_changed_at(time)
        instance_double('Site', _id: 42, last_modified_at: time, cache_enabled: true, cache_control: '', cache_vary: nil)
      end

      it 'tells apart two site changes within the same second' do
        expect(etag_of('steam.site' => site_changed_at(now + 0.001.seconds))).not_to eq etag_of
      end

      it 'is the same for one moment in any time type or zone' do
        moment = now.to_time.utc
        etags  = [moment, moment.getlocal('+03:00'), moment.in_time_zone('Vilnius'), moment.to_datetime].map do |time|
          etag_of('steam.site' => site_changed_at(time))
        end

        expect(etags.uniq).to eq [etag_of]
      end

      it 'tells apart the same path under another mount point' do
        expect(etag_of('SCRIPT_NAME' => '/locomotive/acme/preview')).not_to eq etag_of
      end

      it 'tells apart the same path with another query' do
        expect(etag_of('QUERY_STRING' => 'page=2')).not_to eq etag_of
      end

      it 'tells apart the same path over another scheme' do
        expect(etag_of('rack.url_scheme' => 'https', 'HTTPS' => 'on')).not_to eq etag_of
      end

      it 'tells apart the same path on another host or port' do
        expect(etag_of('HTTP_HOST' => 'sample.example.com')).not_to eq etag_of
        expect(etag_of('HTTP_HOST' => 'models.example.com:8080')).not_to eq etag_of
      end

      it 'is the same for GET and HEAD' do
        expect(etag_of(method: 'HEAD')).to eq etag_of
      end

    end

    context 'the request is a GET' do

      let(:response) { nil }

      before { expect(cache).to receive(:read).with(cache_key).and_return(response) }

      context 'the cache is empty' do

        before { expect(cache).to receive(:write).with(cache_key, Marshal.dump([200, {}, ["Hello world!"]])) }

        it 'tells the CDN to cache the page and also cache it internally' do
          is_expected.to eq ['max-age=0, s-maxage=3600, public, must-revalidate', 'Accept-Language']
        end

        describe 'ETag' do

          subject { send_request[:env]['steam.cache_etag'] }

          it { is_expected.to eq %(W/"#{cache_key}") }

        end

        it 'sends no last modification date' do
          expect(send_request[:env].keys.grep(/last_modified/)).to be_empty
        end

        describe 'the site administrator sets a custom cache control and vary' do

          let(:site) { instance_double('Site', _id: 42, last_modified_at: now, cache_enabled: true, cache_control: 'max-age=600, s-maxage=600, public, must-revalidate', cache_vary: 'Cookie') }

          it 'tells the CDN to cache the page with the custom cache control' do
            is_expected.to eq ['max-age=600, s-maxage=600, public, must-revalidate', 'Cookie']
          end

        end

      end

      describe 'the cache contains the response' do

        let(:response) { Marshal.dump([200, {}, ["Hello world!"]]) }

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
          stored = [stored_code, { 'content-type' => 'text/html', 'x-own' => '1' }.merge(stored_headers), ['Hello world!']]
          allow(cache).to receive(:read).with(cache_key).and_return(Marshal.dump(stored))
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

            it 'answers 304 with the validator and policy the stored copy carries' do
              expect(subject).to eq [304, stored_headers]
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

        before do
          allow(cache).to receive(:read).with(cache_key).and_return(nil)
          allow(cache).to receive(:write)
        end

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

        before { allow(cache).to receive(:read).with(cache_key).and_return(Marshal.dump([200, {}, ['Hello world!']])) }

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
        expect(response[:env]['steam.cache_etag']).to be_nil
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

      before { expect(cache).to receive(:read).with(cache_key).and_return(nil) }

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

      before { expect(cache).to receive(:read).with(cache_key).and_return(nil) }

      it 'keeps no-store' do
        expect(cache).not_to receive(:write)
        expect(send_request[:headers]['cache-control']).to eq 'no-store'
      end

    end

    context 'a render that writes to the session and sets headers of its own' do

      let(:session) { {} }
      let(:app)     { ->(env) { env['rack.session']['csrf.token'] = 't'; [200, { 'etag' => 'W/"own"', 'vary' => 'Cookie', 'x-own' => '1' }, ['t']] } }

      before { expect(cache).to receive(:read).with(cache_key).and_return(nil) }

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
          headers = { 'cache-control' => env['steam.cache_control'], 'vary' => env['steam.cache_vary'],
                      'etag' => env['steam.cache_etag'] }
          [200, headers, ['visitor token']]
        end
      end

      before { expect(cache).to receive(:read).with(cache_key).and_return(nil) }

      it 'serves the page to this visitor only' do
        expect(cache).not_to receive(:write)

        response = send_request

        expect(response[:headers]).to eq('cache-control' => 'max-age=0, private, must-revalidate')
        expect(response[:env]['steam.cache_control']).to eq 'max-age=0, private, must-revalidate'
      end

    end

    context 'a HEAD request that finds no stored copy' do

      let(:method) { 'HEAD' }

      before { expect(cache).to receive(:read).with(cache_key).and_return(nil) }

      it 'keeps the public headers but stores nothing, since a template can render HEAD differently' do
        expect(cache).not_to receive(:write)
        is_expected.to eq ['max-age=0, s-maxage=3600, public, must-revalidate', 'Accept-Language']
      end

    end

    context 'a render that leaves the session empty' do

      let(:session) { {} }

      before do
        expect(cache).to receive(:read).with(cache_key).and_return(nil)
        expect(cache).to receive(:write).with(cache_key, Marshal.dump([200, {}, ['Hello world!']]))
      end

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

      before do
        allow(cache).to receive(:read).and_return(nil)
        expect(cache).not_to receive(:write)
      end

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
