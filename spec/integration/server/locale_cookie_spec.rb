require File.dirname(__FILE__) + '/../integration_helper'

describe Locomotive::Steam::Server do

  include Rack::Test::Methods

  def app
    run_server
  end

  def locale_cookie
    Array(last_response.headers['set-cookie'])
      .flat_map { |header| header.split("\n") }
      .find { |cookie| cookie.start_with?('steam-locale=') }
  end

  describe 'the locale cookie' do

    it 'is not marked Secure over HTTP' do
      get '/index'

      expect(locale_cookie).to start_with('steam-locale=')
      expect(locale_cookie).not_to match(/;\s*secure/i)
    end

    it 'is marked Secure over HTTPS' do
      get 'https://example.org/index'

      expect(locale_cookie).to match(/;\s*secure/i)
    end

    it 'is marked Secure behind a proxy that terminated TLS' do
      [{ 'HTTP_X_FORWARDED_PROTO' => 'https' }, { 'HTTP_X_FORWARDED_SSL' => 'on' }].each do |headers|
        get '/index', {}, headers

        expect(locale_cookie).to match(/;\s*secure/i)
      end
    end

  end

end
