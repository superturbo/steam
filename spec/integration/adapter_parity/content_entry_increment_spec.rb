require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'
require_relative '../../support/adapter_parity_fixture'
require_relative '../../support/adapter_parity_context'

describe 'Adapter parity' do

  shared_examples_for 'the adapter parity dataset' do

    include_context 'adapter parity dataset access'

    describe 'the content entry repository' do

      describe 'writing' do

        include_context 'adapter parity repository writing'

        it 'increments a numeric field' do
          entry = create_specimen

          expect(specimens.inc(entry, :score).score).to eq 42
          expect(specimens.find(entry._id).score).to eq 42
        end

        it 'starts a missing float field at 0.0' do
          entry = create_specimen

          expect(specimens.inc(entry, :price).price).to eq 1.0
          expect(specimens.find(entry._id)[:price]).to eql 1.0
        end

        it 'refuses to increment a number the entry spelled as null' do
          entry = create_specimen(price: nil)

          expect { specimens.inc(entry, :price) }
            .to raise_error(Locomotive::Steam::InvalidIncrement)
          expect(specimens.find(entry._id)[:price]).to be_nil
        end

        it 'updates updated_at along with the number' do
          entry  = create_specimen(updated_at: Time.utc(2000, 1, 1))
          moment = Time.utc(2023, 7, 8, 9, 10, 11.222333444r)

          Timecop.freeze(moment) { specimens.inc(entry, :score) }

          expect(specimens.find(entry._id).updated_at).to eq Time.utc(2023, 7, 8, 9, 10, 11.222r)
          expect(entry.updated_at).to eq Time.utc(2023, 7, 8, 9, 10, 11.222r)
        end

        it 'leaves updated_at alone when the increment is refused' do
          entry = create_specimen(price: nil, updated_at: Time.utc(2000, 1, 1))

          expect { specimens.inc(entry, :price) }
            .to raise_error(Locomotive::Steam::InvalidIncrement)
          expect(specimens.find(entry._id).updated_at).to eq Time.utc(2000, 1, 1)
          expect(entry.updated_at).to eq Time.utc(2000, 1, 1)
        end

        it 'refuses to increment a field that holds no number' do
          expect { specimens.inc(create_specimen, :name, 1) }
            .to raise_error(Locomotive::Steam::InvalidIncrement, 'specimens.name is not a number')
        end

        it 'refuses an amount the field cannot hold' do
          entry = create_specimen

          [[:score, '3'], [:score, 1.5], [:price, '1']].each do |attribute, amount|
            expect { specimens.inc(entry, attribute, amount) }
              .to raise_error(Locomotive::Steam::InvalidIncrement)
          end

          stored = specimens.find(entry._id)
          expect([stored[:score], stored[:price]]).to eq [41, nil]
        end

        # The amount alone leaves the domain, though the sum would not.
        it 'refuses an amount outside the integer domain' do
          entry = create_specimen(score: -1)

          expect { specimens.inc(entry, :score, 2**63) }
            .to raise_error(Locomotive::Steam::InvalidIncrement)
          expect(specimens.find(entry._id)[:score]).to eq(-1)
        end

        # The amount is the default one; the sum is what leaves the domain.
        it 'refuses a result outside the integer domain' do
          entry = create_specimen(score: 2**63 - 1)

          expect { specimens.inc(entry, :score) }
            .to raise_error(Locomotive::Steam::InvalidIncrement)
          expect(specimens.find(entry._id)[:score]).to eq(2**63 - 1)
        end

        # BSON holds Infinity, so no store refuses the overflow on its own.
        it 'refuses a float result the domain cannot hold' do
          entry = create_specimen(price: Float::MAX)

          expect { specimens.inc(entry, :price, Float::MAX) }
            .to raise_error(Locomotive::Steam::InvalidIncrement)
          expect(specimens.find(entry._id)[:price]).to eq Float::MAX
        end

        it 'refuses a stored value of the wrong numeric type' do
          whole    = store_specimen(price: 1)
          fraction = store_specimen(name: 'Fraction', score: 1.5)

          expect { specimens.inc(whole, :price) }
            .to raise_error(Locomotive::Steam::InvalidIncrement)
          expect { specimens.inc(fraction, :score) }
            .to raise_error(Locomotive::Steam::InvalidIncrement)

          expect(specimens.find(whole._id)[:price]).to eql 1
          expect(specimens.find(fraction._id)[:score]).to eql 1.5
        end

        # Ruby absorbs the smaller value, so the sum alone would look finite.
        it 'refuses a float with no room, whatever the sum rounds to' do
          entry = create_specimen(price: 1.0)

          expect { specimens.inc(entry, :price, Float::MAX) }
            .to raise_error(Locomotive::Steam::InvalidIncrement)
          expect(specimens.find(entry._id)[:price]).to eq 1.0
        end

        it 'reaches the ends of the float domain but not past them' do
          reaches = create_specimen(price: -Float::MAX)
          past    = create_specimen(name: 'Past float', price: -1.0)

          expect(specimens.inc(reaches, :price, Float::MAX).price).to eq 0.0
          expect { specimens.inc(past, :price, -Float::MAX) }
            .to raise_error(Locomotive::Steam::InvalidIncrement)
          expect(specimens.find(past._id)[:price]).to eq(-1.0)
        end

        it 'reaches the ends of the integer domain but not past them' do
          reaches = create_specimen(score: -1)
          past    = create_specimen(name: 'Past', score: -2)

          expect(specimens.inc(reaches, :score, -(2**63 - 1)).score).to eq(-2**63)
          expect { specimens.inc(past, :score, -(2**63 - 1)) }
            .to raise_error(Locomotive::Steam::InvalidIncrement)
          expect(specimens.find(past._id)[:score]).to eq(-2)
        end

        it 'reports an entry no longer in the store' do
          entry = create_specimen

          specimens.delete(entry)

          expect { specimens.inc(entry, :score) }
            .to raise_error(Locomotive::Steam::Models::Repository::RecordNotFound)
        end

        it 'reads the value to increment from the store, not from the copy it was given' do
          entry = create_specimen(score: 1)

          moved_on = another_specimens_repository
          moved_on.update(moved_on.find(entry._id).tap { |stored| stored[:score] = 10 })

          expect(specimens.inc(entry, :score).score).to eq 11
        end

        it 'refuses a result the store cannot reach, whatever the copy holds' do
          entry = create_specimen(score: 1)

          moved_on = another_specimens_repository
          moved_on.update(moved_on.find(entry._id).tap { |stored| stored[:score] = 2**63 - 1 })

          expect { specimens.inc(entry, :score) }
            .to raise_error(Locomotive::Steam::InvalidIncrement)
          expect(another_specimens_repository.find(entry._id)[:score]).to eq(2**63 - 1)
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
