require 'spec_helper'

require_relative '../../../lib/locomotive/steam/middlewares/thread_safe'
require_relative '../../../lib/locomotive/steam/middlewares/concerns/helpers'
require_relative '../../../lib/locomotive/steam/middlewares/concerns/csrf_protection'
require_relative '../../../lib/locomotive/steam/middlewares/private_access'

describe Locomotive::Steam::Middlewares::PrivateAccess do

  let(:password)        { nil }
  let(:site)            { instance_double('Site', name: 'Acme Corp', private_access: private_access, password: password) }
  let(:url)             { 'http://models.example.com' }
  let(:lock_screen)     { nil }
  let(:page_finder)     { instance_double('PageFinder', by_handle: lock_screen) }
  let(:services)        { instance_double('Services', page_finder: page_finder) }
  let(:protection)      { true }
  let(:session)         { { Rack::Csrf.key => 'token-1' } }
  let(:app)             { ->(env) { [200, env, ['app']] } }
  let(:middleware)      { described_class.new(app) }
  let(:rack_env)        { build_env }
  let(:method)          { 'GET' }
  let(:form)            { {} }

  before do
    allow(services).to receive(:csrf_protection) { Locomotive::Steam::CsrfProtectionService.new(protection, Rack::Csrf.field, rack_env) }
  end

  subject { code, env, body = middleware.call(rack_env); body.first }

  describe 'no private access enabled' do

    let(:private_access) { false }

    it { is_expected.to eq 'app' }

  end

  describe 'private access enabled' do

    let(:private_access)  { true }

    context 'no password defined' do

      it { is_expected.not_to eq 'app' }

      describe 'with a custom lock screen page' do

        let(:lock_screen) { instance_double('LockScreenPage', title: 'LockScreen') }

        it { subject; expect(rack_env['steam.page'].title).to eq 'LockScreen' }

      end

    end

    context 'password defined' do

      let(:password) { 'easyone' }

      it 'renders a lock screen whose form carries the token of the session' do
        is_expected.to include %(<input type="hidden" name="_csrf" value="token-1" />)
        is_expected.not_to match /Wrong password/
      end

      describe 'a site name and a mount path holding markup' do

        let(:name) { 'Acme</title><script>alert(1)</script> & Co' }
        let(:path) { '/preview" onsubmit="alert(1)' }
        let(:site) { instance_double('Site', name: name, private_access: true, password: password) }

        before { rack_env['steam.mounted_on'] = path }

        it 'renders them as text, adding no element or attribute' do
          html = Nokogiri::HTML5(subject)
          form = html.at_css('form')

          expect(html.css('script')).to be_empty
          expect(html.at_css('title').text).to eq "#{name} - Password protected"
          expect(form.attributes.keys).to eq %w(action method)
          expect(form['action']).to eq path
        end

      end

      describe 'right password submitted with the token' do

        let(:method) { 'POST' }
        let(:form)   { { private_access_password: 'easyone', _csrf: 'token-1' } }

        it { is_expected.to eq 'app' }
        it { subject; expect(session[:private_access_password]).to eq 'easyone'  }

      end

      describe 'right password submitted without the token' do

        let(:method) { 'POST' }
        let(:form)   { { private_access_password: 'easyone' } }

        it 'refuses the form and keeps the site locked' do
          code, _env, body = middleware.call(rack_env)

          expect([code, body.join]).to eq [422, 'The form could not be verified. Reload the page and submit it again.']
          expect(session).not_to have_key(:private_access_password)
        end

      end

      describe 'right password in the query string' do

        let(:form) { { private_access_password: 'easyone', _csrf: 'token-1' } }

        it 'keeps the site locked' do
          is_expected.to include 'name="private_access_password"'
          is_expected.not_to match /Wrong password/
          expect(session).not_to have_key(:private_access_password)
        end

      end

      describe 'right password and token in the form body of a GET request' do

        let(:rack_env) do
          build_env.tap do |env|
            env['CONTENT_TYPE'] = 'application/x-www-form-urlencoded'
            env['rack.input']   = StringIO.new('private_access_password=easyone&_csrf=token-1')
          end
        end

        it 'keeps the site locked' do
          is_expected.to include 'name="private_access_password"'
          expect(session).not_to have_key(:private_access_password)
        end

      end

      describe 'right password already stored in the session' do

        let(:session) { { private_access_password: 'easyone' } }

        it { is_expected.to eq 'app' }
        it { subject; expect(session[:private_access_password]).to eq 'easyone'  }

      end

      describe 'wrong password submitted' do

        let(:method) { 'POST' }
        let(:form)   { { private_access_password: 'wrongone', _csrf: 'token-1' } }

        it { is_expected.to match /Wrong password/ }
        it { subject; expect(session).not_to have_key(:private_access_password) }

      end

      describe 'protection disabled by the host' do

        let(:protection) { false }

        it 'renders a lock screen without a token' do
          is_expected.not_to include 'name="_csrf"'
        end

        describe 'right password submitted without a token' do

          let(:method) { 'POST' }
          let(:form)   { { private_access_password: 'easyone' } }

          it { is_expected.to eq 'app' }

        end

      end

      describe 'feature disabled by a specific rack env variable' do

        before { rack_env['steam.private_access_disabled'] = true }

        it { is_expected.to eq 'app' }

      end

    end

  end

  def build_env
    env_for(url, params: form, method: method).tap do |env|
      env['steam.site']       = site
      env['steam.request']    = Rack::Request.new(env)
      env['steam.services']   = services
      env['rack.session']     = session
    end
  end

end
