require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'
require_relative '../../support/adapter_parity_fixture'
require_relative '../../support/adapter_parity_context'

describe 'Adapter parity' do

  shared_examples_for 'the adapter parity dataset' do

    include_context 'adapter parity dataset access'

    describe 'the content entry repository' do

      it 'counts visible entries by default' do
        expect(specimens.count).to eq 6
      end

      it 'finds one entry by its slug' do
        expect(specimens.by_slug('scalars').name).to eq 'Scalars'
      end

      # The stores use different IDs, even when a slug is a legal ObjectId.
      it 'finds an entry whose slug spells an object id' do
        expect(makers.by_slug('0123456789abcdef01234567').name).to eq 'Hex slug'
      end

      it 'finds an entry by the id it gave it' do
        embedded = specimens.by_slug('embedded')

        expect(specimens.find(embedded._id).name).to eq 'Embedded'
        expect(specimens.all(_id: embedded._id.to_s).map(&:name)).to eq ['Embedded']
      end

      it 'answers whether anything matches a condition' do
        expect(specimens.exists?(flag: true)).to be(true)
      end

      it 'reads the first entry matching a condition' do
        expect(specimens.first(flag: true).name).to eq 'Scalars'
      end

      it 'filters by a belongs_to and by its absence' do
        expect(slugs(maker: 'maker-one')).to match_array %w(arrays scalars)
        expect(slugs(maker: nil)).to match_array %w(all-missing explicit-nils zero)
      end

      # A missing locale must not inherit the default locale's option.
      it 'filters by a localized select through the name each locale gives it' do
        expect(specimens(:en).all(tier: 'Gold').map(&:name)).to eq %w(Embedded Scalars)
        expect(specimens(:fr).all(tier: 'Or').map(&:name)).to eq ['Scalars']
        expect(specimens(:en).all(tier: 'Silver').map(&:name)).to eq ['Arrays']
        expect(specimens(:fr).all(tier: 'Argent').map(&:name)).to eq ['Arrays']
      end

      # A select without the localized flag resolves its option in the default
      # locale, whichever locale asks.
      it 'filters by a non-localized select through the default locale' do
        expect(specimens(:fr).all(category: 'alpha').map(&:name)).to eq ['Scalars']
      end

      it 'groups by a select option, including unused options and entries without one' do
        groups = specimens.group_by_select_option(:category)

        expect(groups.map { |group| group[:name] }).to eq ['alpha', 'beta', 'gamma', nil]
        expect(groups.map { |group| group[:entries].size }).to eq [1, 1, 0, 4]
      end

      it 'filters and orders by a date-time' do
        expect(slugs('at.lte' => Time.utc(2020, 1, 1), order_by: 'at desc')).to eq %w(arrays scalars)
      end

      it 'requires every where clause, including repeated fields' do
        expect(specimens.all { where('score.gt' => 1).where('score.lt' => 8) }.map(&:name))
          .to match_array %w(Embedded Scalars)

        expect(specimens.all { where(name: 'Scalars').where(name: 'Zero') }).to eq []
      end

      it 'filters and orders by a date' do
        expect(slugs('held_on.lte' => Date.new(2020, 1, 1), order_by: 'held_on desc'))
          .to eq %w(arrays scalars)
      end

      # A key holding null exists; a missing key does not.
      describe 'querying by a field presence' do

        it 'tells a stored null from a missing belongs_to' do
          expect(slugs('maker.exists' => true)).to match_array %w(arrays embedded explicit-nils scalars)
          expect(slugs('maker.exists' => false)).to match_array %w(all-missing zero)
        end

        it 'reads a stored null association as nil' do
          expect(specimens.by_slug('explicit-nils').maker.name).to be_nil
        end

        it 'tells a stored null from a missing many_to_many' do
          expect(slugs('topics.exists' => true)).to match_array %w(arrays embedded explicit-nils scalars zero)
          expect(slugs('topics.exists' => false)).to match_array %w(all-missing)
        end

        it 'tells a stored null from a missing select' do
          expect(slugs('category.exists' => true)).to match_array %w(arrays explicit-nils scalars)
          expect(slugs('category.exists' => false)).to match_array %w(all-missing embedded zero)
        end

        it 'tells a stored translation from a missing localized field' do
          expect(slugs('title.exists' => true)).to match_array %w(arrays embedded scalars)
          expect(slugs('title.exists' => false)).to match_array %w(all-missing explicit-nils zero)
        end

        # A locale the source never spelled is missing; one spelled as null exists.
        it 'answers a localized exists for the locale that asks' do
          expect(specimens(:fr).all('title.exists' => true).map(&:name))
            .to match_array ['Embedded', 'Scalars']
          expect(specimens(:fr).all('title.exists' => false).map(&:name))
            .to match_array ['All missing', 'Arrays', 'Explicit nils', 'Zero']
        end

      end

      describe 'querying by visibility' do

        it 'reads only visible entries by default' do
          expect(specimens.all.map(&:name)).not_to include 'Hidden'
        end

        it 'reads the same entries for an explicit true as by default' do
          expect(specimens.all(_visible: true).map(&:name))
            .to eq specimens.all.map(&:name)
        end

        it 'reads only hidden entries for false' do
          expect(specimens.all(_visible: false).map(&:name)).to eq ['Hidden']
        end

        it 'reads every entry, hidden or not, for nil' do
          names = specimens.all(_visible: nil).map(&:name)

          expect(names).to include 'Hidden'
          expect(names.size).to eq 7
        end

        ['true', 'false', 'yes', 0, 1].each do |bad|
          it "rejects #{bad.inspect}" do
            expect { specimens.all(_visible: bad) }
              .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
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
