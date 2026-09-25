require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'

describe 'A password field rendered' do

  let(:site_path) { File.expand_path('../../fixtures/default', __dir__) }
  let(:adapter)   { Locomotive::Steam::FilesystemAdapter.new(site_path).tap { |adapter| adapter.cache = InstanceCacheStore.new } }
  let(:site)      { Locomotive::Steam::SiteRepository.new(adapter).by_handle_or_domain('sample', nil) }
  let(:services)  { Locomotive::Steam::Services.build_instance }
  let(:context) do
    ::Liquid::Context.new({ 'contents' => Locomotive::Steam::Liquid::Drops::ContentTypes.new }, {},
                          { services: services, site: site, locale: :en })
  end

  before do
    services.locale                    = :en
    services.repositories.adapter      = adapter
    services.repositories.current_site = site
  end

  it 'renders nothing in place of the password' do
    source = '{% assign account = contents.accounts.first %}[{{ account.name }}|{{ account.password }}]'

    expect(render_template(source, context)).to eq '[John|]'
  end

end
