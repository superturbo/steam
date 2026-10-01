require 'spec_helper'

require_relative '../../../lib/locomotive/steam/middlewares/thread_safe'

describe Locomotive::Steam::Middlewares::ThreadSafe do

  # A new middleware each time: params are memoized.
  def params_for(body)
    env = Rack::MockRequest.env_for('/', method: 'POST', input: body.to_s, 'CONTENT_TYPE' => 'application/json')
    env.delete('rack.input') if body.nil?
    env['steam.request'] = Rack::Request.new(env)
    described_class.new(nil).tap { |middleware| middleware.env = env }.params
  end

  describe 'the params of a JSON body' do

    it 'reads a JSON object' do
      expect(params_for('{"entry": {"name": "John"}}')).to eq('entry' => { 'name' => 'John' })
    end

    it 'has none for an empty body or no body at all' do
      expect(params_for('')).to eq({})
      expect(params_for(nil)).to eq({})
    end

    it 'puts any other JSON value under _json' do
      expect(params_for('[1, 2]')).to eq('_json' => [1, 2])
      expect(params_for('"text"')).to eq('_json' => 'text')
      expect(params_for('1')).to eq('_json' => 1)
      expect(params_for('null')).to eq('_json' => nil)
      expect(params_for('true')).to eq('_json' => true)
      expect(params_for('false')).to eq('_json' => false)
    end

    ['{"entry": ', " \n", '{"a":' * 1_000 + '1' + '}' * 1_000].each do |body|
      it "refuses #{body[0, 20].inspect} as a bad request, without quoting it" do
        expect { params_for(body) }.to raise_error(Rack::BadRequest) do |error|
          expect(error).to be_a(Locomotive::Steam::InvalidJsonBody)
          expect(error.message).to eq 'The request body is not valid JSON.'
          expect(error.cause).to be_nil
        end
      end
    end

  end

end
