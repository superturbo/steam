require File.dirname(__FILE__) + '/../integration_helper'

describe 'Redirects built from the request path' do

  include Rack::Test::Methods

  def app
    run_server
  end

  def answer(path_info, method: :get)
    send(method, '/', {}, { 'PATH_INFO' => path_info })
    [last_response.status, last_response.location]
  end

  ['//evil.example/', '/\\evil.example/', '/en//evil.example', '/en/\\evil.example'].each do |path|

    it "never sends #{path.inspect} to another host" do
      [:get, :post].each do |method|
        status, location = answer(path, method: method)

        expect(location).to be_nil
        expect(status).to eq 404
      end
    end

  end

  it 'still removes a trailing slash' do
    expect(answer('/about-us/')).to eq [301, '/about-us']
  end

  it 'still removes the default locale, with the query' do
    get '/en/about-us?name=John'
    expect([last_response.status, last_response.location]).to eq [301, '/about-us?name=John']
  end

  it 'still follows a redirect the site configures to another host' do
    expect(answer('/store')).to eq [301, 'http://www.apple.com/en/itunes/']
  end

end
