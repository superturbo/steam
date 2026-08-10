require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'
require_relative '../../support/adapter_parity_fixture'
require_relative '../../support/adapter_parity_context'

describe 'Adapter parity' do

  shared_examples_for 'the adapter parity dataset' do

    include_context 'adapter parity dataset access'

    describe 'the content entry service' do

      include_context 'adapter parity service access'

      it 'lists what a type holds, and narrows it by conditions' do
        expect(service.all('specimens').size).to eq 6
        expect(service.all('specimens', flag: false).size).to eq 3
      end

      it 'lists as json' do
        entry = service.all('specimens', { flag: true }, true).first

        expect(entry.slice('name', 'score')).to eq('name' => 'Scalars', 'score' => 5)
      end

      # Filesystem ids are slugs, so only MongoDB reaches the fallback #find.
      it 'finds an entry by its slug and by the id its store issued' do
        scalars = service.find('specimens', 'scalars')

        expect(scalars.name).to eq 'Scalars'
        expect(service.find('specimens', scalars._id).name).to eq 'Scalars'
      end

      it 'finds an entry whose slug spells an object id' do
        expect(service.find('makers', '0123456789abcdef01234567').name).to eq 'Hex slug'
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
