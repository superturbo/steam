require 'spec_helper'

require_relative '../../../lib/locomotive/steam/middlewares/thread_safe'
require_relative '../../../lib/locomotive/steam/middlewares/concerns/helpers'
require_relative '../../../lib/locomotive/steam/middlewares/logging'

describe Locomotive::Steam::Middlewares::Logging do

  let(:site)        { instance_double('Site', _id: 42, handle: 'acme', name: 'Acme Inc') }
  let(:page)        { instance_double('Page', fullpath: 'products') }
  let(:app)         { ->(env) { [200, env, 'app'] } }
  let(:middleware)  { described_class.new(app) }
  let(:url)         { 'http://models.example.com/products' }

  let(:env) do
    env_for(url, 'steam.site' => site, 'steam.locale' => :en, 'steam.page' => page).tap do |env|
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
      expect(payload[:site_name]).to eq 'Acme Inc'
      expect(payload[:domain]).to eq 'models.example.com'
      expect(payload[:method]).to eq 'GET'
      expect(payload[:locale]).to eq 'en'
      expect(payload[:path]).to eq '/products'
      expect(payload[:page]).to eq 'products'
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

      it 'emits the event with a nil site_id, site_handle, site_name and page' do
        payload = notification_payload_for('steam.http.render') { middleware.call(env) }

        expect(payload[:site_id]).to be_nil
        expect(payload[:site_handle]).to be_nil
        expect(payload[:site_name]).to be_nil
        expect(payload[:page]).to be_nil
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

    it 'logs a conventional [render error] key = value line (name-first)' do
      expect(Locomotive::Common::Logger).to receive(:error).with(
        %r{\[render error\] site = "Acme Inc" / handle = "acme" / host = models\.example\.com / method = GET / path = /products / took = .+ms / error = RuntimeError: boom}
      )
      middleware.call(env) rescue nil
    end

    describe 'a bad request' do

      include_context 'filtered logs'

      let(:exception) { Rack::QueryParser::InvalidParameterError.new('invalid %-encoding (Jonas%zzJonaitis)') }

      it 'names the error by its class, without the message that quotes the request' do
        expect(Locomotive::Common::Logger).to receive(:error).with(
          satisfy { |line| line.end_with?('error = Rack::QueryParser::InvalidParameterError') && !line.include?('Jonas') }
        )
        middleware.call(env) rescue nil
      end

      it 'writes the message too in test mode, as Wagon runs' do
        allow(Locomotive::Steam.configuration).to receive(:mode).and_return(:test)

        expect(Locomotive::Common::Logger).to receive(:error).with(
          satisfy { |line| line.end_with?('error = Rack::QueryParser::InvalidParameterError: invalid %-encoding (Jonas%zzJonaitis)') }
        )
        middleware.call(env) rescue nil
      end

    end

    describe 'with no site resolved in the env' do

      let(:env) do
        env_for(url, 'steam.locale' => :en).tap do |env|
          env['steam.request'] = Rack::Request.new(env)
        end
      end

      it 'logs site = nil with the requested host and re-raises' do
        expect(Locomotive::Common::Logger).to receive(:error).with(
          %r{\[render error\] site = nil / handle = nil / host = models\.example\.com / method = GET / path = /products}
        )
        expect { middleware.call(env) }.to raise_error(RuntimeError, 'boom')
      end

    end

    describe 'with a site that has a blank name' do

      let(:site) { instance_double('Site', _id: 42, handle: 'acme', name: '') }

      it 'logs an empty site name with the handle still present' do
        expect(Locomotive::Common::Logger).to receive(:error).with(
          %r{\[render error\] site = "" / handle = "acme" /}
        )
        middleware.call(env) rescue nil
      end

    end

    it 'emits the steam.render.error event following the Rails convention' do
      payload = notification_payload_for('steam.render.error') do
        middleware.call(env) rescue nil
      end

      expect(payload[:site_id]).to eq 42
      expect(payload[:site_handle]).to eq 'acme'
      expect(payload[:site_name]).to eq 'Acme Inc'
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

  describe 'the params line' do

    include_context 'filtered logs'

    let(:params) do
      {
        auth_action: 'sign_up', auth_content_type: 'accounts', auth_id_field: 'email', auth_password_field: 'slaptazodis',
        auth_id: 'john@doe.net', auth_password: 'Secret1', auth_entry: { name: 'John', slaptazodis: 'Secret2', password_confirmation: 'Secret3' }
      }
    end

    let(:env) do
      env_for(url, method: 'POST', params: params, 'steam.site' => site, 'steam.locale' => :en).tap do |env|
        env['steam.request'] = Rack::Request.new(env)
      end
    end

    let(:lines) { [] }

    before { allow(Locomotive::Common::Logger).to receive(:debug) { |line| lines << line } }

    def params_line
      lines.find { |line| line.include?('Params:') }
    end

    it 'filters the known secret names, the sign-in id and the password field the request names' do
      middleware.call(env)

      expect(params_line).to match(/"name"\s*=>\s*"John"/)
      expect(params_line).not_to include('john@doe.net', 'Secret1', 'Secret2', 'Secret3')
    end

    it "filters the host's list too, as the Engine's request carries it" do
      env['action_dispatch.parameter_filter'] = [:name]
      middleware.call(env)

      expect(params_line).to match(/"name"\s*=>\s*"\[FILTERED\]"/)
    end

    it 'reads no params below the debug level' do
      logger = Locomotive::Common::Logger.instance.logger
      level, logger.level = logger.level, ::Logger::INFO
      expect(env['steam.request']).not_to receive(:params)

      middleware.call(env)

      expect(params_line).to be_nil
    ensure
      logger.level = level
    end

    context 'a malformed form body' do

      let(:env) do
        env_for(url, method: 'POST', input: 'entry[name]=Jonas%zzJonaitis', 'CONTENT_TYPE' => 'application/x-www-form-urlencoded',
                     'steam.site' => site, 'steam.locale' => :en).tap do |env|
          env['steam.request'] = Rack::Request.new(env)
        end
      end

      it 'is left out of the log, and the request goes on' do
        expect(middleware.call(env).first).to eq 200
        expect(params_line).to be_nil
        expect(lines.join).not_to include('Jonas')
      end

    end

    context 'in test mode, as Wagon runs' do

      before { allow(Locomotive::Steam.configuration).to receive(:mode).and_return(:test) }

      it 'writes every value' do
        middleware.call(env)

        expect(params_line).to include('john@doe.net', 'Secret1', 'Secret2', 'Secret3')
      end

    end

    context 'a malformed query string' do

      before { env['QUERY_STRING'] = 'name=Jonas%zzJonaitis' }

      it 'is left out of the log, and the request goes on' do
        expect(middleware.call(env).first).to eq 200
        expect(params_line).to be_nil
        expect(lines.join).not_to include('Jonas')
      end

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
