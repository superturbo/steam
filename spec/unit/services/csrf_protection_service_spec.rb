require 'spec_helper'
require 'rack/csrf'

describe Locomotive::Steam::CsrfProtectionService do

  let(:enabled) { true }
  let(:session) { {} }
  let(:env)     { { 'rack.session' => session } }
  let(:service) { described_class.new(enabled, Rack::Csrf.field, env) }

  describe '#token' do

    it 'stores one token in the session' do
      token = service.token

      expect(token).to be_a(String)
      expect(service.token).to eq token
      expect(session[Rack::Csrf.key]).to eq token
    end

    context 'protection not enabled' do

      let(:enabled) { false }

      it 'has no token and leaves the session untouched' do
        expect(service.token).to be_nil
        expect(session).to be_empty
      end

    end

  end

  describe '#verified?' do

    context 'a token in the session' do

      let(:session) { { Rack::Csrf.key => 'token-1' } }

      it 'accepts the same token' do
        expect(service.verified?('token-1')).to eq true
      end

      it 'refuses another token' do
        expect(service.verified?('token-2')).to eq false
      end

      it 'refuses a missing or blank token' do
        expect(service.verified?(nil)).to eq false
        expect(service.verified?('')).to eq false
      end

      it 'refuses a value that is not text' do
        expect(service.verified?(['token-1'])).to eq false
        expect(service.verified?({ 'a' => 'token-1' })).to eq false
      end

    end

    context 'an empty token in the session' do

      let(:session) { { Rack::Csrf.key => '' } }

      it 'refuses an empty token' do
        expect(service.verified?('')).to eq false
      end

    end

    context 'no token in the session' do

      it 'refuses any token without creating one' do
        expect(service.verified?('token-1')).to eq false
        expect(service.verified?('')).to eq false
        expect(session).to be_empty
      end

    end

    context 'no session' do

      let(:env) { {} }

      it 'refuses the submission' do
        expect(service.verified?('token-1')).to eq false
      end

    end

    context 'protection not enabled' do

      let(:enabled) { false }

      it 'accepts any submission' do
        expect(service.verified?(nil)).to eq true
      end

    end

  end

  describe 'registration' do

    let(:request)  { instance_double('Request', env: env) }
    let(:services) { Locomotive::Steam::Services.build_instance(request) }

    it 'creates no session token until a token is needed' do
      services.csrf_protection

      expect(session).to be_empty
    end

    it 'stays enabled in test mode, which Wagon serves sites in' do
      allow(services.configuration).to receive(:mode).and_return(:test)

      expect(services.csrf_protection.enabled?).to eq true
    end

    context 'protection not enabled' do

      before { allow(services.configuration).to receive(:csrf_protection).and_return(false) }

      it 'is disabled and creates no session token' do
        expect(services.csrf_protection.enabled?).to eq false
        expect(services.csrf_protection.token).to be_nil
        expect(session).to be_empty
      end

    end

  end

end
