require 'spec_helper'

require_relative '../../../../lib/locomotive/steam/middlewares/concerns/helpers'

describe Locomotive::Steam::Middlewares::Concerns::Helpers do

  let(:middleware) do
    Class.new do
      include Locomotive::Steam::Middlewares::Concerns::Helpers
      attr_accessor :env, :request
    end.new.tap do |middleware|
      middleware.env     = Rack::MockRequest.env_for('https://example.com:8443/contact')
      middleware.request = Rack::Request.new(middleware.env)
    end
  end

  describe '#redirect_location' do

    ['/', '/a?b=1', '/fr/contact#form', 'https://example.com:8443/x', 'https://EXAMPLE.COM:8443/x?y=1'].each do |value|

      it "keeps #{value.inspect}" do
        expect(middleware.redirect_location(value, 'success_callback')).to eq value
      end

    end

    ['https://evil.com/x', 'http://example.com:8443/x', 'https://example.com/x', 'https://example.com:8443@evil.com/',
     'https://user@example.com:8443/x', 'HTTPS://example.com:8443/x', '//evil.com/x', '/\\evil.com', 'javascript:alert(1)',
     'contact', '/a b', "/a\nb", "https://example.com:8443/x\n", ['/a']].each do |value|

      it "refuses #{value.inspect}" do
        expect(middleware.redirect_location(value, 'success_callback')).to be_nil
      end

    end

    it 'has none for a missing or blank value, without logging' do
      expect(Locomotive::Common::Logger).not_to receive(:warn)
      expect([nil, '', '  '].map { |value| middleware.redirect_location(value, 'success_callback') }).to eq [nil] * 3
    end

    it 'logs a refusal by name, without the value' do
      expect(Locomotive::Common::Logger).to receive(:warn) do |message|
        expect(message).to include 'success_callback'
        expect(message).not_to include 'evil'
      end

      middleware.redirect_location('https://evil.com/x', 'success_callback')
    end

  end

end
