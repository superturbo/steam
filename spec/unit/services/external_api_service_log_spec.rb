require 'spec_helper'
require 'socket'

describe Locomotive::Steam::ExternalAPIService do

  include_context 'filtered logs'

  let(:service) { described_class.new }
  let(:logged)  { Hash.new { |hash, level| hash[level] = [] } }

  before do
    %i(debug error).each do |level|
      allow(Locomotive::Common::Logger).to receive(level) { |message| logged[level] << message }
    end
  end

  def fail_with(response)
    allow(described_class).to receive(:get).and_return(response)

    service.consume('https://api.example.com:8443/v1/users/tok123?api_key=KEY777', username: 'jdoe', password: 'p456', headers: { 'X-Token' => 'h789' })
  end

  def response_with(body, parsed_response)
    double('response', code: 500, body: body, parsed_response: parsed_response)
  end

  it 'logs a failed call by its method, URL with the query filtered, and status only' do
    fail_with(response_with('{"error":"invalid date"}', { 'error' => 'invalid date' }))

    expect(logged[:error]).to eq ['[WebService] GET https://api.example.com:8443/v1/users/tok123?api_key=[FILTERED] failed with status 500']
  end

  it 'writes the response body at debug level, an object body filtered by name' do
    fail_with(response_with('{"error":"expired","access_token":"T0K9"}', { 'error' => 'expired', 'access_token' => 'T0K9' }))

    expect(logged[:debug].join).to include('[WebService] GET https://api.example.com:8443/v1/users/tok123?api_key=[FILTERED] response: ', 'expired')
    expect(logged[:debug].join).not_to include('T0K9', 'KEY777', 'jdoe', 'p456', 'h789')
  end

  it 'writes any other body as text, cut to a readable length' do
    page = "<html>#{'x' * 5_000}</html>"
    fail_with(response_with(page, page))

    expect(logged[:debug].join).to include('<html>xxx')
    expect(logged[:debug].join.length).to be < 1_200
  end

  it 'logs a 200 answer whose body does not decode by the error class only, and returns nothing' do
    response = double('response', code: 200, body: '<data type="decimal">p456</data>', request: double('request', format: :xml))
    allow(response).to receive(:parsed_response).and_raise(ArgumentError, 'invalid value for BigDecimal(): "p456"')

    expect(fail_with(response)).to be_nil
    expect(logged[:error]).to eq ['[WebService] GET https://api.example.com:8443/v1/users/tok123?api_key=[FILTERED] answered 200 with a body that cannot be read as xml (ArgumentError)']
    expect(logged[:debug].join).to include('[WebService] GET https://api.example.com:8443/v1/users/tok123?api_key=[FILTERED] response: <data type="decimal">p456</data>')
    expect(response).to have_received(:parsed_response).once
  end

  it 'logs the status of a failed call whose body does not parse, and returns nothing' do
    response = double('response', code: 502, body: '<html>Bad gateway</html>')
    allow(response).to receive(:parsed_response).and_raise(JSON::ParserError)

    expect(fail_with(response)).to be_nil
    expect(logged[:error]).to eq ['[WebService] GET https://api.example.com:8443/v1/users/tok123?api_key=[FILTERED] failed with status 502']
    expect(logged[:debug].join).to include('response: <html>Bad gateway</html>')
  end

  it 'logs the status of a real failed call whose JSON body does not parse' do
    server = TCPServer.new('127.0.0.1', 0)
    thread = Thread.new do
      client = server.accept
      while (line = client.gets) && line != "\r\n"; end
      body = '<html>Bad gateway</html>'
      client.write "HTTP/1.1 500 Internal Server Error\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
      client.close
    rescue IOError, SystemCallError
      nil
    end

    expect(service.consume("http://127.0.0.1:#{server.addr[1]}/v1/data?api_key=KEY777")).to be_nil
    expect(logged[:error]).to eq ["[WebService] GET http://127.0.0.1:#{server.addr[1]}/v1/data?api_key=[FILTERED] failed with status 500"]
  ensure
    server&.close
    thread&.join(1)
  end

  describe 'built for a request by the services' do

    let(:env)      { Rack::MockRequest.env_for('/', 'action_dispatch.parameter_filter' => [:access_code]) }
    let(:services) { Locomotive::Steam::Services.build_instance(Rack::Request.new(env)) }

    it "filters the URL of a failed call with the host's rules too" do
      response = double('response', code: 500, body: '<html>Bad gateway</html>')
      allow(response).to receive(:parsed_response).and_raise(JSON::ParserError)
      allow(described_class).to receive(:get).and_return(response)

      expect(services.external_api.consume('https://api.example.com/v1/data?access_code=abc&api_key=KEY777')).to be_nil
      expect(logged[:error]).to eq ['[WebService] GET https://api.example.com/v1/data?access_code=[FILTERED]&api_key=[FILTERED] failed with status 500']
    end

    it "filters an object body at debug level with the host's rules too" do
      allow(described_class).to receive(:get).and_return(response_with('{"error":"x","access_code":"abc"}', { 'error' => 'x', 'access_code' => 'abc' }))

      services.external_api.consume('https://api.example.com/v1/data')

      expect(logged[:debug].join).to match(/"access_code"\s*=>\s*"\[FILTERED\]"/)
      expect(logged[:debug].join).not_to include('abc')
    end

  end

  it "applies Steam's rules without a request" do
    allow(described_class).to receive(:get).and_return(response_with('{"error":"x"}', { 'error' => 'x' }))

    expect(described_class.new.consume('https://api.example.com/v1/data?api_key=KEY777')).to be_nil
    expect(logged[:error]).to eq ['[WebService] GET https://api.example.com/v1/data?api_key=[FILTERED] failed with status 500']
  end

  it 'leaves the body unread below the debug level' do
    logger = Locomotive::Common::Logger.instance.logger
    level, logger.level = logger.level, ::Logger::INFO

    fail_with(double('response', code: 500, parsed_response: 'Bad gateway'))

    expect(logged[:debug]).to be_empty
    expect(logged[:error].size).to eq 1
  ensure
    logger.level = level
  end

end
