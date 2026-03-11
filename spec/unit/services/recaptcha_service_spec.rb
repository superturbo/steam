require 'spec_helper'

describe Locomotive::Steam::RecaptchaService do

  let(:api_url)     { nil }
  let(:secret)      { 'asecretkey' }
  let(:site)        { instance_double('Site',
                        domains: ['example.com'],
                        metafields: {
                          google: {
                             recaptcha_api_url: api_url,
                             'recaptcha_secret' => secret
                          }
                        })
                      }
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

      let(:code)     { '42' }
      let(:response) { { 'success' => false } }

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
          }).and_return(instance_double('Response', parsed_response: response))
        end

        context 'when the API returns a successful response' do

          let(:response) { { 'success' => true, 'score' => 0.9, 'action' => 'contact', 'hostname' => 'example.com' } }

          it { is_expected.to eq(response) }
        end

        context 'when the API returns an unsuccessful response' do

          let(:response) { { 'success' => false, 'error-codes' => ['invalid-input-response'] } }

          it { is_expected.to eq(response) }
        end

        context 'when parsed_response is nil' do

          let(:response) { nil }

          it { is_expected.to eq({}) }
        end
      end

      context 'when metafields recaptcha_secret is blank (falls back to ENV)' do

        let(:secret)          { '' }
        let(:expected_secret) { 'envsecret' }
        let(:response)        { { 'success' => true } }

        before do
          allow(ENV).to receive(:[]).with('RECAPTCHA_SECRET').and_return(expected_secret)

          expect(HTTParty).to receive(:get).with('https://www.google.com/recaptcha/api/siteverify', {
            query: {
              secret:   expected_secret,
              response: '42',
              remoteip: '127.0.0.1'
            }
          }).and_return(instance_double('Response', parsed_response: response))
        end

        it { is_expected.to eq(response) }
      end
    end

    context 'using a different API url' do

      let(:code)     { '42' }
      let(:api_url)  { 'https://recaptcha.net/api' }
      let(:response) { { 'success' => true } }

      before do
        allow(ENV).to receive(:[]).with('RECAPTCHA_SECRET').and_return(nil)

        expect(HTTParty).to receive(:get).with('https://recaptcha.net/api', {
          query: {
            secret:   'asecretkey',
            response: '42',
            remoteip: '127.0.0.1'
          }
        }).and_return(instance_double('Response', parsed_response: response))
      end

      it { is_expected.to eq(response) }
    end

    context 'when the HTTP request fails' do

      let(:code) { '42' }

      before do
        allow(HTTParty).to receive(:get).and_raise(StandardError.new('API error'))
        allow(Locomotive::Common::Logger).to receive(:error)
      end

      it { is_expected.to eq({}) }

      it 'logs the error' do
        subject
        expect(Locomotive::Common::Logger).to have_received(:error)
          .with(/\[Recaptcha\] verify failed: StandardError API error/)
      end
    end
  end
end
