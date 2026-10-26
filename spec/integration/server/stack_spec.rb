require File.dirname(__FILE__) + '/../integration_helper'

describe Locomotive::Steam::Server do

  include Rack::Test::Methods

  def app
    @app ||= run_server
  end

  it 'builds its middlewares once, then serves every request with them' do
    allow(Locomotive::Steam::Middlewares::Page).to receive(:new).and_call_original
    allow(Rack::Session::Moneta).to receive(:new).and_call_original

    2.times do
      get '/'
      expect(last_response.status).to eq 200
    end

    expect(Locomotive::Steam::Middlewares::Page).to have_received(:new).once
    expect(Rack::Session::Moneta).to have_received(:new).once
  end

  it 'answers a HEAD request as it answers a GET, with no body' do
    get '/'
    page = last_response.headers.to_h.slice('content-type', 'cache-control')

    head '/'

    expect([last_response.status, last_response.body, last_response.headers.to_h.slice('content-type', 'cache-control')])
      .to eq [200, '', page]
  end

end
