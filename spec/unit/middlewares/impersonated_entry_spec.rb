require 'spec_helper'

require_relative '../../../lib/locomotive/steam/middlewares/concerns/helpers'
require_relative '../../../lib/locomotive/steam/middlewares/concerns/auth_helpers'
require_relative '../../../lib/locomotive/steam/middlewares/concerns/csrf_protection'
require_relative '../../../lib/locomotive/steam/middlewares/thread_safe'
require_relative '../../../lib/locomotive/steam/middlewares/impersonated_entry'

describe Locomotive::Steam::Middlewares::ImpersonatedEntry do

  let(:site)            { instance_double('Site', _id: 42) }
  let(:url)             { 'http://models.example.com' }
  let(:app)             { ->(env) { env['content-type'] = 'text/html'; [200, env, ['<html><body></body></html>']] } }
  let(:entry)           { nil }
  let(:session)         { {} }
  let(:method)          { 'GET' }
  let(:params)          { {} }
  let(:middleware)      { described_class.new(app) }
  let(:auth_service)    { instance_double('Auth') }
  let(:csrf_enabled)    { true }
  let(:form_token)      { 'form-token' }
  let(:services)        { instance_double('Services', auth: auth_service, csrf_protection: csrf) }
  let(:csrf) do
    instance_double('Locomotive::Steam::CsrfProtectionService', enabled?: csrf_enabled, field: '_csrf', token: form_token).tap do |service|
      allow(service).to receive(:verified?) { |submitted| submitted == form_token }
    end
  end

  let(:posted_stop) { { impersonating: 'stop', _csrf: form_token } }

  subject do
    code, env, body = call
    [env['steam.impersonating_authenticated_entry'], body.first]
  end

  describe 'no impersonation' do

    it { is_expected.to eq [nil, '<html><body></body></html>'] }

    context 'a posted stop' do

      let(:method) { 'POST' }
      let(:params) { posted_stop }

      def stop_without_impersonation
        expect(auth_service).not_to receive(:notify)
        code, headers = call
        [code, headers['location']]
      end

      it 'leaves an anonymous visitor on the page' do
        expect(stop_without_impersonation).to eq [200, nil]
        expect(session).to be_empty
      end

      context 'from a signed in member' do

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

      def banner_form(**options)
        _, _, body = call(**options)
        Nokogiri::HTML5(body.first).at_css('.locomotive-impersonating-banner form')
      end

      it { expect(subject.first).to eq true }
      it { expect(subject.last.gsub(/\s*\n\s+/, ' ')).to include('<body><div class="locomotive-impersonating-banner" ') }

      it 'offers a form that posts the stop and its token to the page' do
        form = banner_form

        expect(form['method']).to eq 'post'
        expect(form.at_css('input[name="impersonating"]')['value']).to eq 'stop'
        expect(form.at_css('input[name="_csrf"]')['value']).to eq form_token
      end

      [
        ['',                         '/fr/about-us',   '/fr/about-us'],
        ['/locomotive/acme/preview', '/fr/about-us',   '/locomotive/acme/preview/fr/about-us'],
        ['',                         '//evil.example', '/'],
        ['',                         '/fr/"about"<us>', '/fr/"about"<us>'],
        ['/locomotive/acme/preview', '//evil.example', '/locomotive/acme/preview//evil.example']
      ].each do |script_name, path_info, action|

        it "posts the stop from #{(script_name + path_info).inspect} to #{action.inspect}, leaving the query out" do
          form = banner_form(script_name: script_name, path_info: path_info, query: 'content_type_slug=messages&auth_action=sign_out')
          expect(form['action']).to eq action
        end

      end

      context 'with a token holding markup' do

        let(:form_token) { 'to"ken<i>' }

        it 'writes the token as the value of one field' do
          form = banner_form

          expect(form.css('input').map { |input| input['name'] }).to eq %w(impersonating _csrf)
          expect(form.at_css('input[name="_csrf"]')['value']).to eq 'to"ken<i>'
        end

      end

      context 'without CSRF protection' do

        let(:csrf_enabled) { false }

        it 'offers the form without a token field' do
          expect(banner_form.at_css('input[name="_csrf"]')).to be_nil
        end

      end

      context 'whose label holds markup' do

        let(:label) { 'John</b><script>alert(1)</script>' }
        let(:entry) { instance_double('Account', _label: label) }

        it 'renders the label as text, adding no element' do
          html = Nokogiri::HTML5(subject.last)

          expect(html.css('script')).to be_empty
          expect(html.at_css('.locomotive-impersonating-banner b').text).to eq label
        end

      end

      context 'whose label holds backslash sequences' do

        let(:entry) { instance_double('Account', _label: 'Account \1 \&') }

        it 'renders the label as it is' do
          expect(Nokogiri::HTML5(subject.last).at_css('.locomotive-impersonating-banner b').text).to eq 'Account \1 \&'
        end

      end

      context 'answering something else than an HTML page' do

        let(:app) { ->(env) { env['content-type'] = 'text/plain'; [200, env, ['<body>plain']] } }

        it 'adds no banner and asks for no token' do
          expect(csrf).not_to receive(:token)
          expect(subject.last).to eq '<body>plain'
        end

      end

      context 'answering an HTML fragment without a body' do

        let(:app) { ->(env) { env['content-type'] = 'text/html'; [200, env, ['<p>fragment</p>']] } }

        it 'adds no banner and asks for no token' do
          expect(csrf).not_to receive(:token)
          expect(subject.last).to eq '<p>fragment</p>'
        end

      end

    end

    describe 'a stop sent by a link' do

      let(:entry)  { instance_double('Account', _label: 'John') }
      let(:params) { { impersonating: 'stop' } }

      it 'keeps the impersonation and shows the page' do
        expect(auth_service).not_to receive(:notify)

        code, = call

        expect([code, session[:authenticated_impersonation]]).to eq [200, '1']
      end

    end

    describe 'a posted stop without a valid token' do

      let(:entry)  { instance_double('Account', _label: 'John') }
      let(:method) { 'POST' }
      let(:params) { { impersonating: 'stop', _csrf: 'another-token' } }

      it 'refuses the form, keeps the impersonation and asks for no token' do
        expect(auth_service).not_to receive(:notify)
        expect(csrf).not_to receive(:token)

        code, _, body = call

        expect([code, body]).to eq [422, ['The form could not be verified. Reload the page and submit it again.']]
        expect(session[:authenticated_impersonation]).to eq '1'
      end

    end

    describe 'a posted stop of a stale impersonation, whose entry is no longer signed in' do

      let(:method) { 'POST' }
      let(:params) { posted_stop }

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

    describe 'an entry submission that renders its errors, with a posted stop' do

      let(:entry)  { instance_double('Account', _label: 'John') }
      let(:method) { 'POST' }
      let(:params) { posted_stop }

      it 'keeps the impersonation' do
        expect(auth_service).not_to receive(:notify)

        code, = call(entry_submission: true)

        expect([code, session[:authenticated_impersonation]]).to eq [200, '1']
      end

    end

    describe 'the administrator posts the stop of the banner' do

      let(:entry)  { instance_double('Account', _label: 'John') }
      let(:method) { 'POST' }
      let(:params) { posted_stop }

      subject do
        code, env, body = call
        [code, env['steam.impersonating_authenticated_entry'], env['location']]
      end

      before do
        expect(auth_service).to receive(:notify).with(:signed_out, any_args).and_return(nil)
      end

      it { is_expected.to eq [303, nil, '/'] }

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

  def call(path_info: nil, steam_path: '/', mounted_on: nil, entry_submission: nil, query: nil, script_name: nil)
    env = env_for(url, method: method, params: params)
    env['SCRIPT_NAME']                  = script_name if script_name
    env['PATH_INFO']                    = path_info if path_info
    env['QUERY_STRING']                 = query if query
    env['steam.mounted_on']             = mounted_on
    env['steam.rendering_entry_errors'] = entry_submission
    env['rack.session']                 = session
    env['steam.site']                   = site
    env['steam.path']                   = steam_path
    env['steam.request']                = Rack::Request.new(env)
    env['steam.liquid_assigns']         = {}
    env['steam.authenticated_entry']    = entry
    env['steam.services']               = services
    middleware.call(env)
  end

end
