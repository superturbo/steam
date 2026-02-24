require 'spec_helper'

describe Locomotive::Steam::RecaptchaService do

  let(:api_url)     { nil }
  let(:secret)      { 'asecretkey' }
  let(:site)        { instance_double('Site', metafields: { google: { recaptcha_api_url: api_url, 'recaptcha_secret' => secret } }) }
  let(:request)     { instance_double('Request', ip: '127.0.0.1') }
  let(:service)     { described_class.new(site, request) }

  before do
    allow(ENV).to receive(:[]).and_call_original
  end

  describe '#verify' do

    let(:code) { nil }

    subject { service.verify(code) }

    it { is_expected.to eq false }

    context 'the code is not nil' do

      let(:code)    { '42' }
      let(:success) { false }

      context 'when metafields recaptcha_secret is present (preferred over ENV)' do

        let(:expected_secret) { 'asecretkey' }

        before do
          allow(ENV).to receive(:[]).with('RECAPTCHA_SECRET').and_return('envsecret')

          expect(HTTParty).to receive(:get).with('https://www.google.com/recaptcha/api/siteverify', {
            query: {
              secret:   expected_secret,
              response: '42',
              remoteip: '127.0.0.1'
            }
          }).and_return(instance_double('Response', parsed_response: { 'success' => success }))
        end

        context 'the code is verified' do

          let(:success) { true }
          it { is_expected.to eq true }

        end

        context 'the code is not verified' do

          let(:success) { false }
          it { is_expected.to eq false }

        end

      end

      context 'when metafields recaptcha_secret is blank (falls back to ENV)' do

        let(:secret)          { '' }
        let(:expected_secret) { 'envsecret' }

        before do
          allow(ENV).to receive(:[]).with('RECAPTCHA_SECRET').and_return(expected_secret)

          expect(HTTParty).to receive(:get).with('https://www.google.com/recaptcha/api/siteverify', {
            query: {
              secret:   expected_secret,
              response: '42',
              remoteip: '127.0.0.1'
            }
          }).and_return(instance_double('Response', parsed_response: { 'success' => success }))
        end

        context 'the code is verified' do

          let(:success) { true }
          it { is_expected.to eq true }

        end

        context 'the code is not verified' do

          let(:success) { false }
          it { is_expected.to eq false }

        end

      end

    end

    context 'using a different API url' do

      let(:code)    { '42' }
      let(:api_url) { 'https://recaptcha.net/api' }

      before do
        allow(ENV).to receive(:[]).with('RECAPTCHA_SECRET').and_return(nil)

        expect(HTTParty).to receive(:get).with('https://recaptcha.net/api', {
          query: {
            secret:   'asecretkey',
            response: '42',
            remoteip: '127.0.0.1'
          }
        }).and_return(instance_double('Response', parsed_response: { 'success' => true }))
      end

      it { is_expected.to eq true }

    end

  end

end
