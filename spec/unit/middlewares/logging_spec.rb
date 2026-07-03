require 'spec_helper'

require_relative '../../../lib/locomotive/steam/middlewares/thread_safe'
require_relative '../../../lib/locomotive/steam/middlewares/concerns/helpers'
require_relative '../../../lib/locomotive/steam/middlewares/logging'

describe Locomotive::Steam::Middlewares::Logging do

  let(:site)        { instance_double('Site', _id: 42, handle: 'acme') }
  let(:app)         { ->(env) { [200, env, 'app'] } }
  let(:middleware)  { described_class.new(app) }
  let(:url)         { 'http://models.example.com/products' }

  let(:env) do
    env_for(url, 'steam.site' => site, 'steam.locale' => :en).tap do |env|
      env['steam.request'] = Rack::Request.new(env)
    end
  end

  describe 'a successful request' do

    subject { middleware.call(env) }

    it 'returns the untouched response of the app' do
      expect(subject.first).to eq 200
      expect(subject.last).to eq 'app'
    end

    it 'emits the steam.http.render event with the full payload' do
      payload = notification_payload_for('steam.http.render') { middleware.call(env) }

      expect(payload[:site_id]).to eq 42
      expect(payload[:site_handle]).to eq 'acme'
      expect(payload[:domain]).to eq 'models.example.com'
      expect(payload[:method]).to eq 'GET'
      expect(payload[:locale]).to eq 'en'
      expect(payload[:path]).to eq '/products'
      expect(payload[:status]).to eq 200
      expect(payload[:time_in_ms]).to be_a(Float)
      expect(payload[:time_in_ms]).to be >= 0.0
    end

    describe 'no site in the env' do

      let(:env) do
        env_for(url, 'steam.locale' => :en).tap do |env|
          env['steam.request'] = Rack::Request.new(env)
        end
      end

      it 'emits the event with a nil site_id and site_handle' do
        payload = notification_payload_for('steam.http.render') { middleware.call(env) }

        expect(payload[:site_id]).to be_nil
        expect(payload[:site_handle]).to be_nil
        expect(payload[:status]).to eq 200
      end

    end

  end

  describe 'the app raises an exception' do

    let(:exception) { RuntimeError.new('boom') }
    let(:app)       { ->(env) { raise exception } }

    it 're-raises the exception' do
      expect { middleware.call(env) }.to raise_error(RuntimeError, 'boom')
    end

    it 'logs the failure at error level so it survives a :warn log level' do
      expect(Locomotive::Common::Logger).to receive(:error).with(/Errored with RuntimeError/)
      middleware.call(env) rescue nil
    end

    it 'emits the steam.render.error event following the Rails convention' do
      payload = notification_payload_for('steam.render.error') do
        middleware.call(env) rescue nil
      end

      expect(payload[:site_id]).to eq 42
      expect(payload[:site_handle]).to eq 'acme'
      expect(payload[:domain]).to eq 'models.example.com'
      expect(payload[:method]).to eq 'GET'
      expect(payload[:locale]).to eq 'en'
      expect(payload[:path]).to eq '/products'
      expect(payload[:time_in_ms]).to be_a(Float)
      expect(payload[:time_in_ms]).to be >= 0.0
      expect(payload[:exception_class]).to eq 'RuntimeError'
      expect(payload[:exception]).to eq ['RuntimeError', 'boom']
      expect(payload[:exception_object]).to be exception
    end

    it 'does not emit the steam.http.render event' do
      payload = notification_payload_for('steam.http.render') do
        middleware.call(env) rescue nil
      end

      expect(payload).to be_nil
    end

  end

  describe '#code_to_human' do

    subject { middleware.send(:code_to_human, code) }

    context 'a code from the original short list' do
      let(:code) { 200 }
      it { is_expected.to eq '200 OK' }
    end

    context 'a code the original list did not cover' do
      let(:code) { 500 }
      it { is_expected.to eq '500 Internal Server Error' }
    end

    context 'another uncovered code' do
      let(:code) { 204 }
      it { is_expected.to eq '204 No Content' }
    end

  end

end
