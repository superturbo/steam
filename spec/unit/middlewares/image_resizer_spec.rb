require 'spec_helper'

require_relative '../../../lib/locomotive/steam/middlewares/image_resizer'

describe Locomotive::Steam::Middlewares::ImageResizer do

  let(:app)        { ->(env) { [404, { 'content-type' => 'text/html' }, ['page not found']] } }
  let(:middleware) { described_class.new(app) }

  it 'leaves a request that is not a resize job to the app, with its answer' do
    status, headers, body = middleware.call(Rack::MockRequest.env_for('/about-us'))

    expect(status).to eq 404
    expect(headers).to eq('content-type' => 'text/html')
    expect(body).to eq ['page not found']
  end

  it 'leaves a request to the app whatever the case of the header that passes it on' do
    allow(::Dragonfly.app(:steam)).to receive(:call).and_return([404, { 'X-Cascade' => 'pass' }, ['Not found']])

    expect(middleware.call(Rack::MockRequest.env_for('/about-us')).last).to eq ['page not found']
  end

end
