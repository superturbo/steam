require 'spec_helper'

require_relative '../../../lib/locomotive/steam/middlewares/thread_safe'
require_relative '../../../lib/locomotive/steam/middlewares/concerns/auth_helpers'
require_relative '../../../lib/locomotive/steam/middlewares/concerns/helpers'
require_relative '../../../lib/locomotive/steam/middlewares/concerns/recaptcha'
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
  let(:session)           { {} }
  let(:form)              { { auth_action: 'sign_up', auth_content_type: 'accounts', :'g-recaptcha-response' => 'mycode' } }
  let(:rack_env)          { build_env }

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

  def build_env
    env_for('http://example.com/account', params: form, method: 'POST').tap do |env|
      env['steam.request']        = Rack::Request.new(env)
      env['steam.site']           = site
      env['steam.services']       = services
      env['rack.session']         = session
      env['steam.liquid_assigns'] = {}
    end
  end

end
