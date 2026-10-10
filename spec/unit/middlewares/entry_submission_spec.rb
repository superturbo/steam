require 'spec_helper'

require_relative '../../../lib/locomotive/steam/middlewares/thread_safe'
require_relative '../../../lib/locomotive/steam/middlewares/concerns/helpers'
require_relative '../../../lib/locomotive/steam/middlewares/concerns/recaptcha'
require_relative '../../../lib/locomotive/steam/middlewares/concerns/csrf_protection'
require_relative '../../../lib/locomotive/steam/middlewares/entry_submission'

describe Locomotive::Steam::Middlewares::EntrySubmission do

  let(:app)                 { ->(env) { [200, env, ['app']] } }
  let(:site)                { instance_double('Site', default_locale: 'en', locales: ['en'], domains: ['example.com'], metafields: { google: {} }) }
  let(:middleware)          { described_class.new(app) }
  let(:recaptcha_enabled)   { false }
  let(:recaptcha_response)  { {} }
  let(:content_type)        { instance_double('ContentType', recaptcha_required?: recaptcha_enabled) }
  let(:service)             { instance_double('EntrySubmissionService') }
  let(:entry_service)       { instance_double('EntryService', get_type: content_type) }
  let(:recaptcha_service)   { instance_double('RecaptchaService', verify: recaptcha_response) }
  let(:services)            { instance_double('Services', entry_submission: service, content_entry: entry_service, recaptcha: recaptcha_service, :locale= => 'en') }
  let(:session)             { { Rack::Csrf.key => 'token-1' } }
  let(:method)              { 'POST' }
  let(:errors)              { instance_double('Error', empty?: false) }
  let(:entry)               { instance_double('Entry', errors: errors, content_type_slug: 'contacts') }
  let(:form)                { { content_type_slug: 'contacts', :'g-recaptcha-response' => 'myrecaptchacode', recaptcha_sitekey: 'mysitekey', _csrf: 'token-1', content: { email: 'john@doe.net' } } }
  let(:url)                 { 'http://example.com/contact-us' }
  let(:rack_env)            { build_env }

  before do
    allow(services).to receive(:csrf_protection) { Locomotive::Steam::CsrfProtectionService.new(true, Rack::Csrf.field, rack_env) }
    allow(service).to receive(:submit).with('contacts', { email: 'john@doe.net' }).and_return(entry)
    allow(entry_service).to receive(:build).with('contacts', { email: 'john@doe.net' }).and_return(entry)
  end

  subject do
    code, env = middleware.call(rack_env)
    [code, env['steam.liquid_assigns']['contact']]
  end

  context 'redirect URL after successful submission' do

    let(:errors)  { instance_double('Error', empty?: true) }
    let(:entry)   { instance_double('Entry', errors: errors, content_type_slug: 'contacts', _slug: 'john') }

    it 'excludes g-recaptcha-response and recaptcha_sitekey from the redirect URL' do
      code, env = middleware.call(rack_env)
      location = env['location']
      expect(location).not_to include('g-recaptcha-response')
      expect(location).not_to include('recaptcha_sitekey')
      expect(location).to include('submitted_type_slug=contacts')
    end

  end

  context 'form token' do

    it 'refuses a submission without a token' do
      form.delete(:_csrf)
      expect(service).not_to receive(:submit)

      code, _headers, body = middleware.call(rack_env)

      expect(code).to eq 422
      expect(body.join).to eq 'The form could not be verified. Reload the page and submit it again.'
    end

    it 'refuses a token other than the one of the session' do
      form[:_csrf] = 'token-2'
      expect(service).not_to receive(:submit)

      expect(middleware.call(rack_env).first).to eq 422
    end

    context 'the token is only in the query string' do

      let(:url) { 'http://example.com/contact-us?_csrf=token-1' }

      it 'refuses the submission' do
        form.delete(:_csrf)
        expect(service).not_to receive(:submit)

        expect(middleware.call(rack_env).first).to eq 422
      end

    end

    it 'accepts the token in the header' do
      form.delete(:_csrf)
      rack_env['HTTP_X_CSRF_TOKEN'] = 'token-1'

      expect(subject).to eq [200, entry]
    end

    it 'accepts the token in the header next to another one in the fields' do
      form[:_csrf] = 'token-2'
      rack_env['HTTP_X_CSRF_TOKEN'] = 'token-1'

      expect(subject).to eq [200, entry]
    end

    it 'accepts the token in the fields next to another one in the header' do
      rack_env['HTTP_X_CSRF_TOKEN'] = 'token-2'

      expect(subject).to eq [200, entry]
    end

    context 'a JSON submission' do

      let(:rack_env) do
        body = JSON.generate(content_type_slug: 'contacts', _csrf: token, content: { email: 'john@doe.net' })
        env_for('http://example.com/contact-us.json', method: 'POST', input: body, 'CONTENT_TYPE' => 'application/json').tap do |env|
          env['steam.request']        = Rack::Request.new(env)
          env['steam.site']           = site
          env['steam.services']       = services
          env['rack.session']         = session
          env['steam.liquid_assigns'] = {}
        end
      end

      before { allow(service).to receive(:to_json).with(entry).and_return('{}') }

      context 'with the token of the session' do

        let(:token)  { 'token-1' }
        let(:errors) { instance_double('Error', empty?: true) }

        it 'creates the entry' do
          expect(service).to receive(:submit).with('contacts', { email: 'john@doe.net' }).and_return(entry)

          expect(middleware.call(rack_env).first).to eq 200
        end

      end

      context 'with another token' do

        let(:token) { 'token-2' }

        it 'refuses the submission with a JSON body' do
          expect(service).not_to receive(:submit)

          code, headers, body = middleware.call(rack_env)

          expect([code, headers['content-type']]).to eq [422, 'application/json']
          expect(JSON.parse(body.join)).to eq('error' => 'The form could not be verified. Reload the page and submit it again.')
        end

        it 'refuses it with a JSON body for a JSON type with parameters on a page path' do
          rack_env['PATH_INFO']    = '/contact-us'
          rack_env['CONTENT_TYPE'] = 'application/json; charset=utf-8'

          code, headers, _body = middleware.call(rack_env)

          expect([code, headers['content-type']]).to eq [422, 'application/json']
        end

      end

    end

  end

  context 'recaptcha has not been enabled' do

    it 'creates a new entry' do
      expect(subject.first).to eq 200
      expect(subject.last).to eq entry
    end

    context 'the form has not been set up for public submission' do

      let(:entry) { nil }

      it 'raises an exception with an explicit error message' do
        expect { subject }.to raise_exception('Unknown content type "contacts" or public_submission_enabled property not true')
      end

    end

  end

  context 'recaptcha has been enabled' do

    let(:recaptcha_enabled) { true }

    context 'the recaptcha response is valid' do

      let(:recaptcha_response) do
        {
          'success' => true,
          'hostname' => 'example.com',
          'action' => 'contacts',
          'score' => 0.9,
          'error-codes' => []
        }
      end

      it 'creates a new entry' do
        expect(recaptcha_service).to receive(:verify).with('myrecaptchacode').and_return(recaptcha_response)
        expect(subject.first).to eq 200
        expect(subject.last).to eq entry
      end

    end

    context 'the recaptcha response is invalid' do

      let(:recaptcha_response) do
        {
          'success' => false,
          'hostname' => 'example.com',
          'action' => 'contacts',
          'score' => 0.1,
          'error-codes' => ['error code']
        }
      end

      it 'returns a 200 code with the invalid entry' do
        expect(errors).to receive(:add).with(:recaptcha_invalid, true)
        expect(subject.first).to eq 200
        expect(subject.last).to eq entry
      end

    end

  end

  def build_env
    env_for(url, params: form, method: method).tap do |env|
      env['steam.request']        = Rack::Request.new(env)
      env['steam.site']           = site
      env['steam.services']       = services
      env['rack.session']         = session
      env['steam.liquid_assigns'] = {}
    end
  end

end
