require 'spec_helper'
require 'socket'

describe Locomotive::Steam::ExternalAPIService do

  let(:service) { described_class.new }

  describe '#consume' do

    let(:url)             { '' }
    let(:options)         { {} }
    let(:code)            { 200 }
    let(:parsed_response) { Hash.new }
    let(:response)        { instance_double('Response', code: code, parsed_response: parsed_response) }

    subject { service.consume(url, options) }

    describe 'sets the base uri from a simple url' do

      let(:url) { 'http://blog.locomotiveapp.org' }
      it do
        expect(service.class).to receive(:get).with('/', { base_uri: 'http://blog.locomotiveapp.org' }).and_return(response)
        subject
      end

      describe 'wrong response (<> 200)' do

        let(:code) { 500 }
        it do
          expect(service.class).to receive(:get).with('/', { base_uri: 'http://blog.locomotiveapp.org' }).and_return(response)
          expect(subject).to eq nil
        end

      end

      describe 'returns a collection instead of a hash' do

        let(:parsed_response) { [{ 'averagePrice' => 1 }] }
        it do
          expect(service.class).to receive(:get).with('/', { base_uri: 'http://blog.locomotiveapp.org' }).and_return(response)
          expect(subject.first['average_price']).to eq 1
        end

      end

    end

    describe 'sets the base uri from a much more complex url' do

      let(:url) { 'http://free.worldweatheronline.com/feed/weather.ashx?key=secretapikey&format=json' }
      it do
        expect(service.class).to receive(:get).with('/feed/weather.ashx?key=secretapikey&format=json', { base_uri: 'http://free.worldweatheronline.com' }).and_return(response)
        subject
      end

    end


    describe 'sets both the base uri and the path from an url with parameters' do

      let(:url) { 'http://blog.locomotiveapp.org/api/read/json?num=3' }
      it do
        expect(service.class).to receive(:get).with('/api/read/json?num=3', { base_uri: 'http://blog.locomotiveapp.org' }).and_return(response)
        subject
      end

    end

    describe 'sets auth credentials' do

      let(:url)     { 'http://blog.locomotiveapp.org' }
      let(:options) { { username: 'john', password: 'foo' } }
      it do
        expect(service.class).to receive(:get).with('/', { base_uri: 'http://blog.locomotiveapp.org', basic_auth: { username: 'john', password: 'foo' } }).and_return(response)
        subject
      end
    end

    describe 'sets authorization header' do

      let(:url)     { 'http://blog.locomotiveapp.org' }
      let(:options) { { header_auth: 'letmein' } }
      it do
        expect(service.class).to receive(:get).with('/', { base_uri: 'http://blog.locomotiveapp.org', headers: { 'Authorization' => 'letmein' } }).and_return(response)
        subject
      end
    end

    describe 'calls an API' do

      let(:url)     { 'https://api.stripe.com/v1/charges' }
      let(:options) {
        {
          method:   'POST',
          data:     { email: 'John Doe', source: '1234567', plan: 'monthly' },
          username: 'abcdefghijkl'
        }
      }

      it do
        expect(service.class).to receive(:post).with('/v1/charges', {
          base_uri: 'https://api.stripe.com',
          body: { email: 'John Doe', source: '1234567', plan: 'monthly' },
          basic_auth: { username: 'abcdefghijkl', password: nil }
        }).and_return(response)
        subject
      end

    end

  end

  it 'waits up to 3 seconds to connect and 3 seconds for each read' do
    expect(described_class.default_options).to include(open_timeout: 3, read_timeout: 3)
  end

  describe 'an API that accepts the connection but never answers' do

    let(:service) { Class.new(described_class) { read_timeout 0.2 }.new }

    it 'is asked once for a page' do
      stalled do |url, connections|
        expect { service.consume(url) }.to raise_error(Net::ReadTimeout)
        expect(connections.size).to eq 1
      end
    end

    it 'is asked once for an action' do
      stalled do |url, connections|
        expect(service.consume(url, {}, true)).to include(status: nil)
        expect(connections.size).to eq 1
      end
    end

    def stalled
      server      = TCPServer.new('127.0.0.1', 0)
      connections = Queue.new
      thread      = Thread.new do
        loop { connections << server.accept }
      rescue IOError, SystemCallError
        nil
      end

      yield "http://127.0.0.1:#{server.addr[1]}/feed", connections
    ensure
      server&.close
      thread&.join(1)
      connections.pop.close until connections.nil? || connections.empty?
    end

  end

end
