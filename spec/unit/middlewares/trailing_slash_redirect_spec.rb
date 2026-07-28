require 'spec_helper'

require_relative '../../../lib/locomotive/steam/middlewares/trailing_slash_redirect'

describe Locomotive::Steam::Middlewares::TrailingSlashRedirect do

  let(:app)        { ->(env) { [200, {}, ['downstream']] } }
  let(:middleware) { described_class.new(app) }

  def call(path, method: 'GET', script_name: nil)
    env = Rack::MockRequest.env_for(path, method: method)
    env['SCRIPT_NAME'] = script_name if script_name
    status, headers, _ = middleware.call(env)
    [status, headers['location']]
  end

  it 'leaves the root path untouched (no redirect loop)' do
    expect(call('/')).to eq [200, nil]
  end

  it 'strips a trailing slash with a 301' do
    expect(call('/foo/')).to eq [301, '/foo']
  end

  it 'keeps the trailing slash when a query string is present' do
    expect(call('/foo/?q=1')).to eq [200, nil]
  end

  it 'strips only one trailing slash' do
    expect(call('/foo//')).to eq [301, '/foo/']
  end

  it 'redirects regardless of the request method' do
    expect(call('/foo/', method: 'POST')).to eq [301, '/foo']
  end

  it 'ignores SCRIPT_NAME in the redirect target' do
    expect(call('/bar/', script_name: '/mounted')).to eq [301, '/bar']
  end

  it 'returns an empty 301 with a zero content length' do
    status, headers, body = middleware.call(Rack::MockRequest.env_for('/foo/'))
    expect(status).to eq 301
    expect(headers).to eq('location' => '/foo', 'content-length' => '0')
    expect(body).to eq []
  end

end
