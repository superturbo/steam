require 'spec_helper'

require_relative '../../../lib/locomotive/steam/middlewares/reset_token_privacy'

describe Locomotive::Steam::Middlewares::ResetTokenPrivacy do

  let(:response)   { [200, { 'content-type' => 'text/html', 'cache-control' => 'max-age=0, s-maxage=3600, public' }, ['page']] }
  let(:app)        { ->(env) { @env = env; response } }
  let(:middleware) { described_class.new(app) }

  def request(query)
    code, headers, = middleware.call(env_for("http://example.com/account/reset-password?#{query}"))
    [code, headers]
  end

  ['auth_reset_token=42a', 'lang=fr&auth_reset_token=42a', 'a=%&auth_reset_token=42a', 'auth%5Freset_token=42a',
   '%61uth_reset_token=42a', 'a=%&auth%5Freset_token=42a', 'a[]=1&a[x]=2&auth_reset_token=42a',
   'auth_reset_token[]=42a', 'auth_reset_token[x]=42a', 'auth_reset_token'].each do |query|

    it "keeps the answer to #{query.inspect} out of caches and referrers" do
      _, headers = request(query)

      expect(headers).to eq(
        'content-type'    => 'text/html',
        'cache-control'   => 'no-store',
        'referrer-policy' => 'no-referrer'
      )
      expect(@env['steam.no_store']).to eq true
    end

  end

  context 'a redirect' do

    let(:response) { [301, { 'location' => '/account/reset-password?auth_reset_token=42a' }, []] }

    it 'keeps it out of caches and referrers too' do
      expect(request('auth_reset_token=42a')).to eq [301, {
        'location'        => '/account/reset-password?auth_reset_token=42a',
        'cache-control'   => 'no-store',
        'referrer-policy' => 'no-referrer'
      }]
    end

  end

  ['', 'lang=fr', 'my_auth_reset_token=42a', 'auth_reset_tokens=42a'].each do |query|

    it "leaves the answer to #{query.inspect} as it is" do
      expect(request(query)).to eq response.first(2)
      expect(@env).not_to have_key('steam.no_store')
    end

  end

end
