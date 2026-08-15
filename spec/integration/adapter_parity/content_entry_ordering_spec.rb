require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'
require_relative '../../support/adapter_parity_fixture'
require_relative '../../support/adapter_parity_context'

describe 'Adapter parity' do

  shared_examples_for 'the adapter parity dataset' do

    include_context 'adapter parity dataset access'

    describe 'the content entry repository' do

      it 'reads the ends of its own order' do
        expect(specimens.first.name).to eq 'All missing'
        expect(specimens.last.name).to eq 'Zero'
      end

      it 'orders by a field' do
        expect(slugs(order_by: 'name')).to eq %w(all-missing arrays embedded explicit-nils scalars zero)
      end

      it 'orders the rows with no number after the ones with zero' do
        expect(slugs(order_by: 'score.desc, name'))
          .to eq %w(arrays embedded scalars zero all-missing explicit-nils)
      end

      # Scalars and Embedded tie at score 5.
      it 'breaks a tie by position, ascending and descending alike' do
        expect(slugs(order_by: 'score'))
          .to eq %w(all-missing explicit-nils zero scalars embedded arrays)
        expect(slugs(order_by: 'score.desc'))
          .to eq %w(arrays embedded scalars zero explicit-nils all-missing)
      end

      it 'preserves an explicit slug direction' do
        expect(slugs(order_by: '_slug.desc'))
          .to eq %w(zero scalars explicit-nils embedded arrays all-missing)
      end

      # Mongo would keep the last direction, the filesystem the first.
      it 'refuses a field named twice in the sequence' do
        expect { slugs(order_by: 'score.asc, score.desc') }
          .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
      end

      it 'reverses that order however the direction is spelled' do
        descending = %w(zero scalars explicit-nils embedded arrays all-missing)

        expect(slugs(order_by: 'name.desc')).to eq descending
        expect(slugs(order_by: { name: -1 })).to eq descending
      end

      # True, then false, then the rows with no value at all.
      it 'orders by a field and a direction, breaking the tie with a second' do
        expect(slugs(order_by: 'flag.desc, name'))
          .to eq %w(scalars arrays embedded zero all-missing explicit-nils)
      end

      describe 'windowing' do

        it 'takes the first rows of its own order' do
          expect(specimens.all { limit(2) }.map(&:name)).to eq ['All missing', 'Arrays']
        end

        it 'skips the rows before the window' do
          expect(specimens.all { offset(4) }.map(&:name)).to eq %w(Scalars Zero)
        end

        it 'skips before it takes' do
          expect(specimens.all { offset(1).limit(2) }.map(&:name)).to eq %w(Arrays Embedded)
        end

        it 'returns no rows for a zero limit' do
          expect(specimens.all { limit(0) }).to eq []
          expect(specimens.first { limit(0) }).to be_nil
        end

        it 'validates criteria for a zero limit' do
          expect { specimens.all('$where' => 'sleep(1)') { limit(0) } }
            .to raise_error(Locomotive::Steam::Adapters::Query::UnsupportedOperator)
        end

        it 'refuses a window it cannot describe' do
          [-> { specimens.all { limit(-1) } },
           -> { specimens.all { offset(-1) } },
           -> { specimens.all { limit('2') } }].each do |query|
            expect(&query).to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
          end
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
