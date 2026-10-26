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

end
