require 'spec_helper'

require_relative '../../../lib/locomotive/steam/middlewares/concerns/helpers'
require_relative '../../../lib/locomotive/steam/middlewares/concerns/auth_helpers'
require_relative '../../../lib/locomotive/steam/middlewares/thread_safe'
require_relative '../../../lib/locomotive/steam/middlewares/impersonated_entry'

describe Locomotive::Steam::Middlewares::ImpersonatedEntry do

  let(:site)            { instance_double('Site', _id: 42) }
  let(:url)             { 'http://models.example.com' }
  let(:app)             { ->(env) { [200, env, ['<html><body></body></html>']] } }
  let(:entry)           { nil }
  let(:session)         { {} }
  let(:params)          { {} }
  let(:middleware)      { described_class.new(app) }
  let(:auth_service)    { instance_double('Auth') }
  let(:services)        { instance_double('Services', :auth => auth_service) }

  subject do
    code, env, body = call
    [env['steam.impersonating_authenticated_entry'], body.first]
  end

  describe 'no impersonation' do

    it { is_expected.to eq [nil, '<html><body></body></html>'] }

    context 'with a link to stop impersonating' do

      let(:params) { { impersonating: 'stop' } }

      def stop_without_impersonation
        expect(auth_service).not_to receive(:notify)
        code, headers = call
        [code, headers['location']]
      end

      it 'leaves an anonymous visitor on the page' do
        expect(stop_without_impersonation).to eq [200, nil]
        expect(session).to be_empty
      end

      context 'for a signed in member' do

        let(:session) { { authenticated_entry_type: 'accounts', authenticated_entry_id: '42' } }
        let(:entry)   { instance_double('Account', _label: 'John') }

        it 'keeps the member signed in on the page' do
          expect(stop_without_impersonation).to eq [200, nil]
          expect(session).to eq(authenticated_entry_type: 'accounts', authenticated_entry_id: '42')
        end

      end

    end

  end

  describe 'impersonating is on' do

    let(:session) { { authenticated_impersonation: '1', authenticated_entry_type: 'accounts' } }

    context 'the account is not logged in' do

      it { is_expected.to eq [nil, '<html><body></body></html>'] }

    end

    context 'the account is logged in' do

      let(:entry) { instance_double('Account', _label: 'John') }

      it { expect(subject.first).to eq true }
      it { expect(subject.last.gsub(/\s*\n\s+/, ' ')).to include('<body><div class="locomotive-impersonating-banner" ') }

      context 'whose label holds markup' do

        let(:label) { 'John</b><script>alert(1)</script>' }
        let(:entry) { instance_double('Account', _label: label) }

        it 'renders the label as text, adding no element' do
          html = Nokogiri::HTML5(subject.last)

          expect(html.css('script')).to be_empty
          expect(html.at_css('.locomotive-impersonating-banner b').text).to eq label
        end

      end

    end

    describe 'a link to stop a stale impersonation, whose entry is no longer signed in' do

      let(:params) { { impersonating: 'stop' } }

      [{ authenticated_impersonation: '1', authenticated_entry_type: 'accounts' }, { authenticated_impersonation: '1' }].each do |stale|

        context "with #{stale.keys.join(' and ')}" do

          let(:session) { stale.dup }

          it 'signs nobody out and leaves the visitor on the page' do
            expect(auth_service).not_to receive(:notify)
            code, headers = call

            expect([code, headers['location']]).to eq [200, nil]
            expect(session.slice(:authenticated_entry_type, :authenticated_entry_id))
              .to eq stale.slice(:authenticated_entry_type, :authenticated_entry_id)
          end

        end

      end

    end

    describe 'an entry submission that renders its errors, with a link to stop impersonating' do

      let(:entry)  { instance_double('Account', _label: 'John') }
      let(:params) { { impersonating: 'stop' } }

      it 'keeps the impersonation' do
        expect(auth_service).not_to receive(:notify)

        code, = call(entry_submission: true)

        expect([code, session[:authenticated_impersonation]]).to eq [200, '1']
      end

    end

    describe 'the administrator wants to leave the impersonating mode' do

      let(:entry) { instance_double('Account', _label: 'John') }
      let(:params) { { impersonating: 'stop' } }

      subject do
        code, env, body = call
        [code, env['steam.impersonating_authenticated_entry'], env['location']]
      end

      before do
        expect(auth_service).to receive(:notify).with(:signed_out, any_args).and_return(nil)
      end

      it { is_expected.to eq [302, nil, '/'] }

      it 'ends the impersonating mode of the session' do
        subject
        expect(session).not_to have_key(:authenticated_impersonation)
      end

      [
        ['/fr/about-us',    '/about-us',      nil,                         '/fr/about-us'],
        ['//evil.example',  '//evil.example', nil,                         '/'],
        ['/\\evil.example', '/\\evil.example', nil,                        '/'],
        ['/locomotive/acme/preview/fr/about-us', '/about-us', '/locomotive/acme/preview', '/locomotive/acme/preview/fr/about-us']
      ].each do |path_info, steam_path, mounted_on, location|

        it "sends the administrator from #{path_info.inspect} back to #{location.inspect}, on the site" do
          _, headers = call(path_info: path_info, steam_path: steam_path, mounted_on: mounted_on)
          expect(headers['location']).to eq location
        end

      end

      it 'does not redirect under a mount path a browser would read as another host' do
        code, headers = call(path_info: '//evil.example/fr', steam_path: '/fr', mounted_on: '//evil.example')
        expect([code, headers['location']]).to eq [200, nil]
      end

    end

  end

  def call(path_info: nil, steam_path: '/', mounted_on: nil, entry_submission: nil)
    env = env_for(url, params: params)
    env['PATH_INFO']                  = path_info if path_info
    env['steam.mounted_on']           = mounted_on
    env['steam.rendering_entry_errors'] = entry_submission
    env['rack.session']               = session
    env['steam.site']                 = site
    env['steam.path']                 = steam_path
    env['steam.request']              = Rack::Request.new(env)
    env['steam.liquid_assigns']       = {}
    env['steam.authenticated_entry']  = entry
    env['steam.services'] = services
    middleware.call(env)
  end

end
