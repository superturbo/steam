require 'spec_helper'

describe Locomotive::Steam::CookieService do

  let(:steam_cookies)   { {} }
  let(:request_cookies) { {} }
  let(:ssl)             { false }
  let(:request)         { instance_double('Request', env: { 'steam.cookies' => steam_cookies }, cookies: request_cookies, ssl?: ssl) }
  let(:service)         { described_class.new(request) }

  describe '#get' do

    let(:request_cookies) { { 'foo' => 'bar' } }

    it 'reads a cookie of the request' do
      expect(service.get('foo')).to eq 'bar'
    end

    it 'reads a cookie set this request, whatever its keys' do
      service.set('foo', { 'value' => 'bar2' })
      expect(service.get('foo')).to eq 'bar2'

      service.set('foo', { value: 'bar3' })
      expect(service.get('foo')).to eq 'bar3'
    end

  end

  describe '#set' do

    it 'keeps the values under symbols, leaving the given ones as they are' do
      given = { 'value' => 'bar2', 'path' => '/' }

      service.set('foo', given)

      expect(steam_cookies).to eq('foo' => { value: 'bar2', path: '/', secure: false })
      expect(given).to eq('value' => 'bar2', 'path' => '/')
    end

    context 'over HTTPS' do

      let(:ssl) { true }

      it 'marks the cookie secure unless told otherwise' do
        service.set('kept', { 'value' => '1' })
        service.set('unsaid', { 'value' => '2', 'secure' => nil })
        service.set('plain', { 'value' => '3', 'secure' => false })

        expect(steam_cookies['kept'][:secure]).to eq true
        expect(steam_cookies['unsaid'][:secure]).to eq true
        expect(steam_cookies['plain'][:secure]).to eq false
      end

    end

  end

end
