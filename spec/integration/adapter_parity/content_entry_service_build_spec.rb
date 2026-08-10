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

      describe 'writing' do

        include_context 'adapter parity service writing'

        it 'builds an entry without persisting it' do
          entry = service.build('submissions', valid)

          expect(entry['name']).to eq 'Ada'
          expect(entry['errors']).to be_blank
          expect(service.all('submissions').size).to eq 0
        end

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
