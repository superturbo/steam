require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'

describe 'Entries read by an action' do

  let(:site_path) { File.expand_path('../../fixtures/default', __dir__) }
  let(:adapter)   { Locomotive::Steam::FilesystemAdapter.new(site_path).tap { |adapter| adapter.cache = InstanceCacheStore.new } }
  let(:site)      { Locomotive::Steam::SiteRepository.new(adapter).by_handle_or_domain('sample', nil) }
  let(:services)  { Locomotive::Steam::Services.build_instance(instance_double('Request', env: {})) }
  let(:context) do
    ::Liquid::Context.new({ 'contents' => Locomotive::Steam::Liquid::Drops::ContentTypes.new }, {},
                          { services: services, site: site, locale: :en })
  end

  before do
    allow(Locomotive::Steam.configuration).to receive(:asset_host).and_return('https://assets.example.com')
    services.locale                    = :en
    services.current_site              = site
    services.repositories.adapter      = adapter
    services.repositories.current_site = site
  end

  it 'gives a file field the URL the page shows' do
    source = "{% action 'cover' %}setProp('cover', findEntry('songs', 'song-number-1').cover.url);{% endaction %}" \
             "{% with_scope _slug: 'song-number-1' %}{% for song in contents.songs %}" \
             '[{{ cover }}][{{ song.cover.url }}]' \
             '{% endfor %}{% endwith_scope %}'

    expect(render_template(source, context)).to eq '[https://assets.example.com/samples/asset_collections/cover.jpg]' \
                                                   '[https://assets.example.com/samples/asset_collections/cover.jpg]'
  end

end
