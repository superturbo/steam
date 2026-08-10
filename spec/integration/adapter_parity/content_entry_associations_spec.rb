require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'
require_relative '../../support/adapter_parity_fixture'
require_relative '../../support/adapter_parity_context'

describe 'Adapter parity' do

  shared_examples_for 'the adapter parity dataset' do

    include_context 'adapter parity dataset access'

    describe 'the content entry repository' do

      # Source states: missing, null, [], [nil], [id, nil], and linked ids.
      describe 'querying a many_to_many by nil' do

        # A lone nil is currently coerced to an empty list.
        it 'matches only the emptied list' do
          expect(slugs(topics: nil)).to eq %w(zero)
        end

        it 'negates the emptied list' do
          expect(slugs('topics.ne' => nil))
            .to match_array %w(all-missing arrays embedded explicit-nils scalars)
        end

        it 'matches nothing through in' do
          expect(slugs('topics.in' => nil)).to eq []
        end

        it 'matches everything through nin' do
          expect(slugs('topics.nin' => nil))
            .to match_array %w(all-missing arrays embedded explicit-nils scalars zero)
        end

        it 'matches nothing through all' do
          expect(slugs('topics.all' => nil)).to eq []
        end

        # Explicit lists keep exact-list equality.
        it 'matches the emptied list through an explicit empty list' do
          expect(slugs(topics: [])).to eq %w(zero)
        end

        it 'matches the null element through an explicit null list' do
          expect(slugs(topics: [nil])).to eq %w(embedded)
        end

        it 'matches the mixed list through the same explicit list' do
          expect(slugs(topics: ['topic-b', nil])).to eq %w(arrays)
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
