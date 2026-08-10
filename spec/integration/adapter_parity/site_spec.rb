require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'
require_relative '../../support/adapter_parity_fixture'
require_relative '../../support/adapter_parity_context'

describe 'Adapter parity' do

  shared_examples_for 'the adapter parity dataset' do

    include_context 'adapter parity dataset access'

    describe 'the site' do

      it 'is found by the domain the fixture declares' do
        expect(site_repository.by_domain('adapter-parity.example.com').handle).to eq 'adapter-parity'
      end

      it 'exposes the same public attributes' do
        expect(site.name).to eq 'Adapter parity'
        expect(site.handle).to eq 'adapter-parity'
        expect(site.locales).to eq %i(en fr)
        expect(site.default_locale).to eq :en
        expect(site.timezone_name).to eq 'UTC'
      end

    end

  end

  context 'MongoDB' do

    before(:all) { AdapterParityFixture.seed_mongodb! }
    after(:all)  { AdapterParityFixture.cleanup! }

    it_should_behave_like 'the adapter parity dataset' do
      let(:adapter)  { AdapterParityFixture.mongodb_adapter }

      def filesystem?; false; end
    end

  end

  context 'Filesystem' do

    it_should_behave_like 'the adapter parity dataset' do
      let(:adapter) { AdapterParityFixture.filesystem_adapter }

      def filesystem?; true; end
    end

  end

end
