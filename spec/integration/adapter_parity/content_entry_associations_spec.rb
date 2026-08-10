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

        # A lone nil reaches the operator layer untouched; the emptied list is
        # a value of its own, not a shade of nil.
        it 'matches a missing, null, or null-holding list through nil' do
          expect(slugs(topics: nil))
            .to match_array %w(all-missing arrays embedded explicit-nils)
        end

        it 'negates nil to the lists free of nulls' do
          expect(slugs('topics.ne' => nil)).to match_array %w(scalars zero)
        end

        it 'treats in nil as in [null]' do
          expect(slugs('topics.in' => nil))
            .to match_array %w(all-missing arrays embedded explicit-nils)
        end

        it 'treats nin nil as its complement' do
          expect(slugs('topics.nin' => nil)).to match_array %w(scalars zero)
        end

        it 'treats all nil as all [null]' do
          expect(slugs('topics.all' => nil))
            .to match_array %w(all-missing arrays embedded explicit-nils)
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
