require 'spec_helper'

require_relative '../../../lib/locomotive/steam/middlewares/thread_safe'
require_relative '../../../lib/locomotive/steam/middlewares/concerns/auth_helpers'
require_relative '../../../lib/locomotive/steam/middlewares/concerns/helpers'
require_relative '../../../lib/locomotive/steam/middlewares/concerns/recaptcha'
require_relative '../../../lib/locomotive/steam/middlewares/concerns/csrf_protection'
require_relative '../../../lib/locomotive/steam/middlewares/auth'

describe Locomotive::Steam::Middlewares::Auth::AuthOptions do

  let(:metafields)  { { 'smtp' => { 'address' => '127.0.0.1', 'user_name' => 'John', 'password' => 'doe', 'port' => 25 } } }
  let(:site)        { instance_double('Site', metafields: metafields) }
  let(:params)      { {} }

  let(:options) { described_class.new(site, params) }

  describe '#smtp' do

    subject { options.smtp }

    it { is_expected.to eq(
        address: '127.0.0.1',
        user_name: 'John',
        password: 'doe',
        port: 25,
        authentication: 'plain',
        enable_starttls_auto: false,
    ) }

    context 'no smtp metafields' do

      let(:metafields) { {} }

      it { is_expected.to eq({}) }

    end

  end

  describe '#password_field' do

    it 'names no field a visitor left out, so the type chooses its own' do
      expect(options.password_field).to be_nil
    end

    context 'a visitor naming one' do

      let(:params) { { auth_password_field: 'secret' } }

      it { expect(options.password_field).to eq :secret }

    end

  end

end

describe Locomotive::Steam::Middlewares::Auth do

  let(:app)               { ->(env) { [200, env, ['app']] } }
  let(:middleware)        { described_class.new(app) }
  let(:site)              { instance_double('Site', default_locale: 'en', locales: ['en'], domains: ['example.com'], metafields: { google: {} }) }
  let(:content_type)      { instance_double('ContentType', recaptcha_required?: true) }
  let(:entry_service)     { instance_double('EntryService', get_type: content_type) }
  let(:recaptcha_response) do
    { 'success' => false, 'hostname' => 'example.com', 'action' => 'accounts', 'score' => 0.1, 'error-codes' => ['error code'] }
  end
  let(:recaptcha_service) { instance_double('RecaptchaService', verify: recaptcha_response) }
  let(:auth_service)      { instance_double('AuthService', find_authenticated_resource: nil) }
  let(:services)          { instance_double('Services', auth: auth_service, content_entry: entry_service, recaptcha: recaptcha_service, :locale= => 'en') }
  let(:session)           { { Rack::Csrf.key => 'token-1' } }
  let(:form)              { { auth_action: 'sign_up', auth_content_type: 'accounts', :'g-recaptcha-response' => 'mycode', _csrf: 'token-1' } }
  let(:request_method)    { 'POST' }
  let(:url)               { 'http://example.com/account' }
  let(:rack_env)          { build_env }

  before do
    allow(services).to receive(:csrf_protection) { Locomotive::Steam::CsrfProtectionService.new(true, Rack::Csrf.field, rack_env) }
  end

  describe 'request method' do

    let(:request_method) { 'GET' }

    %w(sign_up sign_in sign_out forgot_password reset_password).each do |action|

      it "runs no #{action} for a GET request carrying a valid token" do
        form[:auth_action] = action
        rack_env['HTTP_X_CSRF_TOKEN'] = 'token-1'
        expect(auth_service).to receive(:find_authenticated_resource)

        code, env = middleware.call(rack_env)

        expect(code).to eq 200
        expect(env['steam.liquid_assigns'].keys.grep(/\Aauth_/)).to be_empty
      end

    end

    context 'a POST whose method an override turned into DELETE' do

      let(:request_method) { 'POST' }
      let(:form)   { { auth_action: 'sign_in', auth_content_type: 'accounts', _csrf: 'token-1' } }

      it 'runs the action' do
        rack_env['REQUEST_METHOD'] = 'DELETE'
        rack_env['rack.methodoverride.original_method'] = 'POST'
        expect(auth_service).to receive(:sign_in).and_return(:wrong_credentials)

        middleware.call(rack_env)
      end

    end

    context 'a DELETE request' do

      let(:request_method) { 'DELETE' }
      let(:form)   { { auth_action: 'sign_in', auth_content_type: 'accounts', _csrf: 'token-1' } }

      it 'runs no action' do
        expect(middleware.call(rack_env).first).to eq 200
      end

    end

  end

  describe 'form token' do

    before { allow(auth_service).to receive(:sign_up) }

    it 'refuses an action without a token' do
      form.delete(:_csrf)

      code, _headers, body = middleware.call(rack_env)

      expect([code, body.join]).to eq [422, 'The form could not be verified. Reload the page and submit it again.']
      expect(recaptcha_service).not_to have_received(:verify)
      expect(auth_service).not_to have_received(:sign_up)
    end

    it 'refuses a token other than the one of the session' do
      form[:_csrf] = 'token-2'

      expect(middleware.call(rack_env).first).to eq 422
      expect(auth_service).not_to have_received(:sign_up)
    end

    it 'leaves a request without an authentication action alone' do
      form.replace(_csrf: 'token-2')

      expect(middleware.call(rack_env).first).to eq 200
    end

  end

  describe 'sign_up with an invalid recaptcha' do

    before do
      allow(auth_service).to receive(:sign_up)
      expect(recaptcha_service).to receive(:verify).with('mycode').and_return(recaptcha_response)
    end

    it 'appends the invalid recaptcha message and does not sign the visitor up' do
      _code, env = middleware.call(rack_env)

      assigns = env['steam.liquid_assigns']
      expect(assigns['auth_invalid_recaptcha_code']).to eq('auth_invalid_recaptcha_code')
      expect(assigns['recaptcha_invalid']).to eq(true)
      expect(auth_service).not_to have_received(:sign_up)
    end

  end

  describe 'reset_password of a type whose password field has another name' do

    let(:form)         { { auth_action: 'reset_password', auth_content_type: 'accounts', auth_reset_token: '42', auth_callback: '/me', _csrf: 'token-1' } }
    let(:content_type) { instance_double('ContentType', slug: 'accounts', recaptcha_required?: false) }
    let(:entry)        { instance_double('Account', _id: 42, content_type: content_type) }

    before { allow(auth_service).to receive(:reset_password).and_return([:secret_reset, entry]) }

    it 'signs the visitor in and follows the callback' do
      code, headers = middleware.call(rack_env)

      expect(session[:authenticated_entry_id]).to eq '42'
      expect([code, headers['location']]).to eq [303, '/me']
    end

  end

  describe 'a successful action without a callback' do

    let(:content_type) { instance_double('ContentType', slug: 'accounts', recaptcha_required?: false) }
    let(:entry)        { instance_double('Account', _id: 42, content_type: content_type) }

    def redirection
      code, headers = middleware.call(rack_env)
      [code, headers['location']]
    end

    before do
      allow(auth_service).to receive(:sign_in).and_return([:signed_in, entry])
      allow(auth_service).to receive(:reset_password).and_return([:password_reset, entry])
    end

    %w(sign_in reset_password).each do |action|

      context action do

        before { form[:auth_action] = action }

        it 'sends the visitor to the home page with a See Other' do
          expect(redirection).to eq [303, '/']
        end

        it 'reads a blank callback as none' do
          form[:auth_callback] = '  '
          expect(redirection).to eq [303, '/']
        end

        it 'reads a callback leaving the site as none' do
          form[:auth_callback] = 'https://evil.com/x'
          expect(redirection).to eq [303, '/']
        end

        it 'follows an absolute URL of the site as it is, under a mount path too' do
          form[:auth_callback] = 'http://example.com/account/me'
          rack_env['steam.mounted_on'] = '/locomotive/acme/preview'
          expect(redirection).to eq [303, 'http://example.com/account/me']
        end

        it 'reads a URL whose scheme it would not follow as absolute as none' do
          form[:auth_callback] = 'HTTP://example.com/account/me'
          rack_env['steam.mounted_on'] = '/locomotive/acme/preview'
          expect(redirection).to eq [303, '/locomotive/acme/preview/']
        end

        it 'sends the visitor to the home page of a mounted site' do
          rack_env['steam.mounted_on'] = '/locomotive/acme/preview'
          expect(redirection).to eq [303, '/locomotive/acme/preview/']
        end

      end

    end

    describe 'sign_out' do

      let(:url)      { 'http://example.com/fr/account' }
      let(:rack_env) { build_env.tap { |env| env['steam.path'] = '/account' } }

      before do
        allow(auth_service).to receive(:find_authenticated_resource).and_return(entry)
        allow(auth_service).to receive(:sign_out)
        session.merge!(authenticated_entry_type: 'accounts', authenticated_entry_id: '42')
        form[:auth_action] = 'sign_out'
      end

      it 'ends an impersonation the session holds' do
        session[:authenticated_impersonation] = '1'
        middleware.call(rack_env)
        expect(session).not_to have_key(:authenticated_impersonation)
      end

      it 'sends the visitor back to the page, its locale included' do
        expect(redirection).to eq [303, '/fr/account']
      end

      it 'reads a blank callback as none' do
        form[:auth_callback] = ''
        expect(redirection).to eq [303, '/fr/account']
      end

      it 'reads a callback leaving the site as none' do
        form[:auth_callback] = '//evil.com/x'
        expect(redirection).to eq [303, '/fr/account']
      end

      ['//evil.com/x', '/\\evil.com/x'].each do |path|

        it "sends the visitor to the home page from #{path.inspect}, a path browsers read as another host" do
          rack_env['PATH_INFO'] = path
          expect(redirection).to eq [303, '/']
        end

      end

      it 'sends the visitor back to the page of a mounted site' do
        rack_env['steam.mounted_on'] = '/locomotive/acme/preview'
        expect(redirection).to eq [303, '/locomotive/acme/preview/fr/account']
      end

      it 'sends the visitor to the home page from the mount path itself' do
        rack_env['steam.mounted_on'] = '/locomotive/acme/preview'
        rack_env['PATH_INFO']        = ''
        expect(redirection).to eq [303, '/locomotive/acme/preview/']
      end

    end

  end

  describe 'forgot_password' do

    let(:form)     { { auth_action: 'forgot_password', auth_content_type: 'accounts', auth_id: 'john@doe.net', _csrf: 'token-1' } }
    let(:rack_env) { build_env.tap { |env| env['steam.locale'] = 'en' } }

    before do
      allow(site).to receive(:to_liquid).and_return({})
      allow(services).to receive(:repositories)
    end

    it 'tells the page the instructions were sent' do
      allow(auth_service).to receive(:forgot_password).and_return(:reset_password_instructions_sent)

      _, env = middleware.call(rack_env)

      expect(env['steam.liquid_assigns']).to eq('auth_reset_password_instructions_sent' => 'auth_reset_password_instructions_sent')
    end

    it 'answers 503 when the site has no reset link' do
      allow(auth_service).to receive(:forgot_password).and_return(:reset_password_unavailable)

      code, headers, body = middleware.call(rack_env)

      expect([code, headers['content-type'], body.join]).to eq [503, 'text/plain', 'The password cannot be reset at the moment.']
    end

  end

  def build_env
    env_for(url, params: form, method: request_method).tap do |env|
      env['steam.request']        = Rack::Request.new(env)
      env['steam.site']           = site
      env['steam.services']       = services
      env['rack.session']         = session
      env['steam.liquid_assigns'] = {}
    end
  end

end
