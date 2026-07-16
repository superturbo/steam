require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'
require_relative '../../support/examples/query_parity'

describe 'Query parity' do

  context 'MongoDB' do

    it_should_behave_like 'canonical query parity' do
      let(:adapter) { Locomotive::Steam::MongoDBAdapter.new(database: mongodb_database, hosts: ['127.0.0.1:27017']) }
      let(:site_id) { mongodb_site_id }
    end

  end

  context 'Filesystem' do

    it_should_behave_like 'canonical query parity' do
      let(:adapter) { Locomotive::Steam::FilesystemAdapter.new(default_fixture_site_path) }
      let(:site_id) { 1 }

      after(:all) { Locomotive::Steam::Adapters::Filesystem::SimpleCacheStore.new.clear }
    end

  end

end
