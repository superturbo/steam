require 'spec_helper'

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
