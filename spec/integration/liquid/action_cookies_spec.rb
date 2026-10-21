require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'

describe 'Cookies an action sets' do

  let(:site_path) { File.expand_path('../../fixtures/default', __dir__) }
  let(:adapter)   { Locomotive::Steam::FilesystemAdapter.new(site_path).tap { |adapter| adapter.cache = InstanceCacheStore.new } }
  let(:site)      { Locomotive::Steam::SiteRepository.new(adapter).by_handle_or_domain('sample', nil) }
  let(:request)   { Rack::Request.new(Rack::MockRequest.env_for('https://example.org/')) }
  let(:services)  { Locomotive::Steam::Services.build_instance(request) }
  let(:context) do
    ::Liquid::Context.new({}, {}, { services: services, site: site, locale: :en })
  end

  before do
    services.locale                    = :en
    services.current_site              = site
    services.repositories.adapter      = adapter
    services.repositories.current_site = site
  end

  it 'reads in the same action a cookie it has just set, secure over HTTPS' do
    source = "{% action 'remember' %}setCookiesProp('visitor', { 'value': 'first' });" \
             "setProp('visitor', getCookiesProp('visitor'));{% endaction %}[{{ visitor }}]"

    expect(render_template(source, context)).to eq '[first]'
    expect(request.env['steam.cookies']['visitor']).to eq(value: 'first', secure: true)
  end

end
