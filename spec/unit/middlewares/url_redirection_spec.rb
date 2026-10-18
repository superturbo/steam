require 'spec_helper'

require_relative '../../../lib/locomotive/steam/middlewares/thread_safe'
require_relative '../../../lib/locomotive/steam/middlewares/concerns/helpers'
require_relative '../../../lib/locomotive/steam/middlewares/url_redirection'

describe Locomotive::Steam::Middlewares::UrlRedirection do

  let(:redirections)    { [] }
  let(:site)            { instance_double('Site', _id: 42, url_redirections: redirections) }
  let(:url)             { 'http://models.example.com' }
  let(:locomotive_path) { nil }
  let(:app)             { ->(env) { [200, env, 'app'] } }
  let(:middleware)      { described_class.new(app) }

  subject do
    env = env_for(url, 'steam.site' => site)
    env['steam.request']    = Rack::Request.new(env)
    env['locomotive.path']  = locomotive_path
    code, env = middleware.call(env)
    [code, env['location']]
  end

  def redirected(rules, path, query = '', extra_env = {})
    site = instance_double('Site', _id: 42, url_redirections: rules)
    env  = env_for('http://models.example.com/', 'steam.site' => site).merge('PATH_INFO' => path, 'QUERY_STRING' => query, **extra_env)
    env['steam.request'] = Rack::Request.new(env)
    code, env = middleware.call(env)
    [code, env['location']]
  end

  describe 'no redirections' do

    it { is_expected.to eq [200, nil] }

  end

  describe 'exact rules' do

    it 'matches a rule with a query against the path and the query as sent' do
      rules = [['/contact?city=springfield', '/contact/springfield']]

      expect(redirected(rules, '/contact', 'city=springfield')).to eq [301, '/contact/springfield']
      expect(redirected(rules, '/other', 'city=springfield', 'locomotive.path' => '/contact')).to eq [301, '/contact/springfield']
      expect(redirected(rules, '/contact', 'city=springfield&utm=1')).to eq [200, nil]
      expect(redirected(rules, '/contact', 'city=springfiel%64')).to eq [200, nil]
      expect(redirected([['/k?a=1&b=2', '/x']], '/k', 'b=2&a=1')).to eq [200, nil]
      expect(redirected([['/k?q=a%20b', '/x']], '/k', 'q=a+b')).to eq [200, nil]
      expect(redirected([['/k?q=a+b', '/x']], '/k', 'q=a%20b')).to eq [200, nil]
    end

    it 'matches a rule without a query against the path, whatever the query' do
      rules = [['/foo.php', '/bar']]

      expect(redirected(rules, '/foo.php', 'a=1')).to eq [301, '/bar']
      expect(redirected(rules, '/other', 'a=1', 'locomotive.path' => '/foo.php')).to eq [301, '/bar']
      expect(redirected(rules, '/foo.php', '', 'SCRIPT_NAME' => '/site')).to eq [301, '/bar']
    end

    it 'takes the rule with the query first, then the rule of the path, then a dynamic rule' do
      rules = [['/old/:id', '/dynamic/:id'], ['/old/5', '/path'], ['/old/5?x=1', '/query']]

      expect(redirected(rules, '/old/5', 'x=1')).to eq [301, '/query']
      expect(redirected(rules, '/old/5', 'x=2')).to eq [301, '/path']
      expect(redirected(rules, '/old/6', 'x=1')).to eq [301, '/dynamic/6']
    end

  end

  describe 'dynamic rules, read literally' do

    ['/a(b/:id', '/a[b/:id', '/files/:1'].each do |source|

      it "leaves an unrelated page alone with the rule #{source.inspect}" do
        expect(redirected([[source, '/new/:id']], '/about/us')).to eq [200, nil]
      end

    end

    {
      ['/a(b/:id', '/a(b/5']        => [301, '/new/5'],
      ['/c++/:id', '/c++/5']        => [301, '/new/5'],
      ['/old.html/:id', '/old.html/5'] => [301, '/new/5'],
      ['/old.html/:id', '/oldXhtml/5'] => [200, nil],
      ['/files/:1', '/files/:1']    => [301, '/new/:id']
    }.each do |(source, path), answer|

      it "matches #{source.inspect} as written for #{path.inspect}" do
        expect(redirected([[source, '/new/:id']], path)).to eq answer
      end

    end

    it 'matches the whole path, from its start to its end' do
      expect(redirected([['/old/:id', '/new/:id']], '/x/old/5')).to eq [200, nil]
      expect(redirected([['/old/:id.html', '/new/:id']], '/old/5.htmlx')).to eq [200, nil]
      expect(redirected([['/old/:id.html', '/new/:id']], '/old/5.html')).to eq [301, '/new/5']
    end

    it 'lets a parameter take a part of a segment, never a /' do
      expect(redirected([['/old/:id', '/new/:id']], '/old/5/6')).to eq [200, nil]
      expect(redirected([['/v/:major.:minor', '/n/:major/:minor']], '/v/1.2')).to eq [301, '/n/1/2']
    end

    it 'takes no rule with parameters side by side or a name used twice as dynamic' do
      expect(redirected([['/x/:a:b', '/n/:a/:b']], '/x/12')).to eq [200, nil]
      expect(redirected([['/a/:id/:id', '/b/:id']], '/a/1/2')).to eq [200, nil]
    end

    it 'matches the path only, whatever the query' do
      expect(redirected([['/old/:id', '/new/:id']], '/old/5', 'x=1')).to eq [301, '/new/5']
    end

    it 'takes no rule with a query as dynamic' do
      expect(redirected([['/k?c=:city', '/k/:city']], '/k', 'c=springfield')).to eq [200, nil]
    end

    it 'puts each value in the target once, by its whole name' do
      expect(redirected([['/a/:id/:id2', '/b/:id/:id2']], '/a/1/2')).to eq [301, '/b/1/2']
      expect(redirected([['/a/:x/:y', '/b/:x/:y']], '/a/:y/2')).to eq [301, '/b/:y/2']
      expect(redirected([['/a/:id', '/b/:id?ref=:source']], '/a/5')).to eq [301, '/b/5?ref=:source']
    end

    ['/new?ref=:id', 'https://example.org/new?ref=:id'].each do |target|

      it "puts a value in the query of #{target.inspect} as one query value, decoded once" do
        query = ->(path) { Rack::Utils.parse_query(redirected([['/go/:id', target]], path).last.split('?', 2).last) }

        {
          '/go/a&admin=1'     => 'a&admin=1',
          '/go/a%26admin%3D1' => 'a&admin=1',
          '/go/%2526'         => '%26',
          '/go/50%25'         => '50%',
          '/go/a+b'           => 'a+b',
          '/go/a%20b'         => 'a b',
          '/go/caf%C3%A9'     => 'café'
        }.each { |path, value| expect(query.(path)).to eq('ref' => value) }
      end

    end

    it 'puts a value in the path and the fragment of the target as the path carries it' do
      expect(redirected([['/go/:id', '/new/:id']], '/go/a&b=1')).to eq [301, '/new/a&b=1']
      expect(redirected([['/go/:id', '/new/:id']], '/go/50%25')).to eq [301, '/new/50%25']
      expect(redirected([['/go/:id', 'https://example.org/new/:id']], '/go/a%20b')).to eq [301, 'https://example.org/new/a%20b']
      expect(redirected([['/go/:id', '/new?x=1#:id']], '/go/a%20b')).to eq [301, '/new?x=1#a%20b']
    end

    it 'reads a colon before a digit as text' do
      expect(redirected([['/files/:1', '/new/:1']], '/files/x')).to eq [200, nil]
    end

    it 'reads a name up to its first character outside the grammar' do
      expect(redirected([['/files/:file.png', '/img/:file.png']], '/files/cat.png')).to eq [301, '/img/cat.png']
      expect(redirected([['/files/:id-x', '/n/:id-x']], '/files/5-x')).to eq [301, '/n/5-x']
    end

    it 'never lets a value give a target without an authority one' do
      expect(redirected([['/go/:to', '/:to']], '/go/\\evil.example')).to eq [200, nil]
      expect(redirected([['/go/:to', '/:to/page']], "/go/\t")).to eq [200, nil]
      expect(redirected([['/go/:to', ':to']], '/go/\\\\evil.example')).to eq [200, nil]
      expect(redirected([['/go/:to', ':to']], '/go/https:evil.example')).to eq [200, nil]
      expect(redirected([['/go/:to', 'https:///:to']], '/go/evil.example')).to eq [200, nil]
    end

    it 'never fills in the authority a target writes, its user info and IPv6 address included' do
      expect(redirected([['/go/:db8', 'https://[2001:db8::1]/new/:db8']], '/go/5')).to eq [301, 'https://[2001:db8::1]/new/5']
      expect(redirected([['/go/:pass', 'https://user:pass@example.org/:pass']], '/go/5')).to eq [301, 'https://user:pass@example.org/5']
    end

    it 'leaves a parameter written in a target authority as text, the rule being wrong' do
      expect(redirected([['/go/:to', 'https://:to']], '/go/evil.example')).to eq [301, 'https://:to']
      expect(redirected([['/go/:to', 'foo://host\\:to']], '/go/@evil.example')).to eq [301, 'foo://host\\:to']
    end

    it 'never answers a location holding raw whitespace or control characters' do
      expect(redirected([['/go/:id', 'https://example.org/:id']], "/go/a\r\nSet-Cookie:x")).to eq [200, nil]
      expect(redirected([['/go/:id', 'https://example.org/:id']], '/go/a b')).to eq [200, nil]
      expect(redirected([['/go/:id', '/new/:id']], "/go/a\r\nSet-Cookie:x")).to eq [200, nil]
    end

    it 'puts values after the authority a target writes' do
      expect(redirected([['/go/:id', 'https://example.org/:id']], '/go/5')).to eq [301, 'https://example.org/5']
      expect(redirected([['/go/:id', 'https://example.org?ref=:id']], '/go/5')).to eq [301, 'https://example.org?ref=5']
      expect(redirected([['/go/:id', '//cdn.example/:id']], '/go/5')).to eq [301, '//cdn.example/5']
      expect(redirected([['/go/:id', 'https://[2001:db8::1]/new/:id']], '/go/5')).to eq [301, 'https://[2001:db8::1]/new/5']
      expect(redirected([['/go/:id', 'https://user:pass@example.org/:id']], '/go/5')).to eq [301, 'https://user:pass@example.org/5']
      expect(redirected([['/go/:id', 'https://example.org']], '/go/5')).to eq [301, 'https://example.org']
    end

    it 'skips a rule giving no location for the value for the next one' do
      expect(redirected([['/go/:to', '/:to'], ['/go/:id', '/x/:id']], '/go/\\evil.example')).to eq [301, '/x/\\evil.example']
    end

    it 'follows a relative target' do
      expect(redirected([['/old/:id', 'new/:id']], '/old/5')).to eq [301, 'new/5']
      expect(redirected([['/go/:to', ':to']], '/go/page')).to eq [301, 'page']
    end

    it 'follows a target without values as written' do
      expect(redirected([['/old/:id', 'new']], '/old/5')).to eq [301, 'new']
      expect(redirected([['/old/:id', 'mailto:info@example.org']], '/old/5')).to eq [301, 'mailto:info@example.org']
    end

    it 'reads locomotive.path first, and never the query' do
      expect(redirected([['/old/:id', '/new/:id']], '/other', 'x=1', 'locomotive.path' => '/old/5')).to eq [301, '/new/5']
    end

  end

  describe 'redirections' do

    let(:redirections) { [['/foo.php', '/bar']] }

    it { is_expected.to eq [200, nil] }

    describe 'use first the locomotive.path env variable' do

      let(:locomotive_path) { '/foo.php' }
      it { is_expected.to eq [301, '/bar'] }

    end

    describe 'requesting the old url' do

      let(:url) { 'http://models.example.com/foo.php' }
      it { is_expected.to eq [301, '/bar'] }

      describe 'url with a lot of dots' do

        let(:redirections) { [['/content.HOME.HOME.WELCOME.DEU.GER.html', '/bar'], ['/hello', '/world']] }
        let(:url) { 'http://models.example.com/content.HOME.HOME.WELCOME.DEU.GER.html' }

        it { is_expected.to eq [301, '/bar'] }

      end

      describe 'and redirecting to an external url' do

        let(:redirections) { [['/foo.php', 'https://rickandmorty.dev']] }
        let(:url) { 'http://models.example.com/foo.php' }

        it { is_expected.to eq [301, 'https://rickandmorty.dev'] }

      end

      describe 'url matching a pattern' do

        let(:redirections) { [['/old_images/:file', '/images/old/:file']] }
        let(:url) { 'http://models.example.com/old_images/cat.png' }

        it { is_expected.to eq [301, '/images/old/cat.png'] }

      end

      describe 'the same dynamic pattern reused across requests' do

        let(:redirections) { [['/old_images/:file', '/images/old/:file']] }

        it 'substitutes per-request without mutating the shared redirection target' do
          run = ->(path) {
            env = env_for("http://models.example.com#{path}", 'steam.site' => site)
            env['steam.request'] = Rack::Request.new(env)
            code, env = middleware.call(env)
            [code, env['location']]
          }

          expect(run.('/old_images/cat.png')).to eq [301, '/images/old/cat.png']
          expect(run.('/old_images/dog.png')).to eq [301, '/images/old/dog.png']
        end

      end

      describe 'let the parent app know about the redirection when it happens' do

        let(:events) { [] }

        before {
          @subscriber = ActiveSupport::Notifications.subscribe('steam.serve.url_redirection') do |name, start, finish, id, payload|
            events << payload[:url]
          end
        }

        after { ActiveSupport::Notifications.unsubscribe(@subscriber) }

        it 'emits an event' do
          subject
          expect(events).to eq ['/foo.php']
        end

      end

      describe 'url with a query string' do

        let(:url) { 'http://models.example.com/foo.php?a=1' }

        it { is_expected.to eq [301, '/bar'] }

        describe 'exact matching' do

          let(:redirections) { { '/foo.php?a=1' => '/bar' } }
          it { is_expected.to eq [301, '/bar'] }

        end

      end

    end

  end

end
