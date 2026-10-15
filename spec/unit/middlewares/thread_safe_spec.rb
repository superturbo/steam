require 'spec_helper'

require_relative '../../../lib/locomotive/steam/middlewares/thread_safe'

describe Locomotive::Steam::Middlewares::ThreadSafe do

  # A new middleware each time: params are memoized.
  def middleware_for(body)
    env = Rack::MockRequest.env_for('/', method: 'POST', input: body.to_s, 'CONTENT_TYPE' => 'application/json')
    env.delete('rack.input') if body.nil?
    env['steam.request'] = Rack::Request.new(env)
    described_class.new(nil).tap { |middleware| middleware.env = env }
  end

  def params_for(body)
    middleware_for(body).params
  end

  describe 'the params of a request' do

    def middleware_with(url, body, content_type, env = nil)
      env ||= Rack::MockRequest.env_for(url, method: 'POST', input: body, 'CONTENT_TYPE' => content_type)
      env['steam.request'] ||= Rack::Request.new(env)
      described_class.new(nil).tap { |middleware| middleware.env = env }
    end

    {
      'a form'      => ['name=body&id=body', 'application/x-www-form-urlencoded'],
      'a JSON body' => ['{"name": "body", "id": "body"}', 'application/json']
    }.each do |kind, (body, content_type)|

      it "reads the query, #{kind} and the route, each over the one before" do
        middleware = middleware_with('/?name=query&id=query&q=1', body, content_type)
        expect(middleware.params['id']).to eq 'body'

        middleware.merge_route_params('id' => 'route')
        middleware.merge_route_params('page' => '2')

        expect(middleware.params.to_h).to eq('name' => 'body', 'id' => 'route', 'q' => '1', 'page' => '2')
      end

    end

    it 'reads a body as JSON for the JSON media type only' do
      with_charset = middleware_with('/', '{"name": "x"}', 'application/json; charset=utf-8')
      other_type   = middleware_with('/', '{"name": "x"}', 'application/jsonx')

      expect([with_charset.params['name'], other_type.params['name']]).to eq ['x', nil]
    end

    it 'keeps the route params for any later middleware, also once the request params change' do
      middleware = middleware_with('/?a=1', 'b=2', 'application/x-www-form-urlencoded')
      middleware.merge_route_params('id' => 'route')
      middleware.request.update_param('c', '3')

      expect(middleware_with(nil, nil, nil, middleware.env).params.to_h).to eq('a' => '1', 'b' => '2', 'c' => '3', 'id' => 'route')
    end

  end

  describe 'the params of a JSON body' do

    it 'reads a JSON object' do
      expect(params_for('{"entry": {"name": "John"}}')).to eq('entry' => { 'name' => 'John' })
    end

    it 'parses the body once for the params and the body fields' do
      middleware = middleware_for('{"_csrf": "token-1"}')
      expect(JSON).to receive(:parse).once.and_call_original

      expect(middleware.params['_csrf']).to eq 'token-1'
      expect(middleware.body_params['_csrf']).to eq 'token-1'
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
