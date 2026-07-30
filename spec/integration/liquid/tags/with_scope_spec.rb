require 'spec_helper'

require_relative '../../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../../../lib/locomotive/steam/adapters/mongodb.rb'

describe Locomotive::Steam::Liquid::Tags::WithScope do

  describe 'grouping a collection by a select field, one scope per loop iteration' do

    let(:source) { "{% for opt in contents.bands.kind_options %}[{{ opt }}:{% with_scope kind: opt %}{{ contents.bands.count }}:{% for band in contents.bands %}{{ band.leader }} {% endfor %}{% endwith_scope %}]{% endfor %}" }

    let(:site)      { Locomotive::Steam::Site.new(_id: site_id, locales: %w(en fr nb), default_locale: 'en') }
    let(:services)  { Locomotive::Steam::Services.build_instance }
    let(:assigns)   { { 'contents' => Locomotive::Steam::Liquid::Drops::ContentTypes.new } }
    let(:context)   { ::Liquid::Context.new(assigns, {}, { services: services, locale: :en, site: site }) }
    let(:cache)     { Locomotive::Steam::Adapters::Filesystem::SimpleCacheStore.new }

    before do
      cache.clear
      services.locale = :en
      services.repositories.adapter       = adapter
      services.repositories.current_site  = site
    end

    after { cache.clear }

    subject { render_template(source, context) }

    shared_examples_for 'a per-iteration select-option scope' do
      it { is_expected.to eq '[grunge:2:Layne Eddie ][rock:1:Peter ][country:0:]' }
    end

    context 'Filesystem' do
      it_should_behave_like 'a per-iteration select-option scope' do
        let(:site_id) { 1 }
        let(:adapter) { Locomotive::Steam::FilesystemAdapter.new(default_fixture_site_path) }
      end
    end

    context 'MongoDB' do
      it_should_behave_like 'a per-iteration select-option scope' do
        let(:site_id) { mongodb_site_id }
        let(:adapter) { Locomotive::Steam::MongoDBAdapter.new(database: mongodb_database, hosts: ['127.0.0.1:27017']) }
      end
    end

  end

  describe 'the documented all syntax against an array field' do

    let(:site)      { Locomotive::Steam::Site.new(_id: site_id, locales: %w(en fr nb), default_locale: 'en') }
    let(:services)  { Locomotive::Steam::Services.build_instance }
    let(:assigns)   { { 'contents' => Locomotive::Steam::Liquid::Drops::ContentTypes.new } }
    let(:context)   { ::Liquid::Context.new(assigns, {}, { services: services, locale: :en, site: site }) }
    let(:cache)     { Locomotive::Steam::Adapters::Filesystem::SimpleCacheStore.new }

    before do
      cache.clear
      services.locale = :en
      services.repositories.adapter       = adapter
      services.repositories.current_site  = site
    end

    after { cache.clear }

    subject { render_template(source, context) }

    shared_examples_for 'the same rows for both forms' do
      context 'the canonical array form' do
        let(:source) { "{% with_scope tags.all: ['awesome', 'open bar'] %}{{ contents.events.count }}{% endwith_scope %}" }
        it { is_expected.to eq '2' }
      end

      context 'the legacy string form' do
        let(:source) { %({% with_scope tags.all: "$and: ['awesome', 'open bar']" %}{{ contents.events.count }}{% endwith_scope %}) }
        it { is_expected.to eq '2' }
      end
    end

    context 'Filesystem' do
      it_should_behave_like 'the same rows for both forms' do
        let(:site_id) { 1 }
        let(:adapter) { Locomotive::Steam::FilesystemAdapter.new(default_fixture_site_path) }
      end
    end

    context 'MongoDB' do
      it_should_behave_like 'the same rows for both forms' do
        let(:site_id) { mongodb_site_id }
        let(:adapter) { Locomotive::Steam::MongoDBAdapter.new(database: mongodb_database, hosts: ['127.0.0.1:27017']) }
      end
    end

  end

end
