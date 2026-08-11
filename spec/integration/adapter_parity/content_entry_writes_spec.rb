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

        it 'adds an entry a later read can see' do
          entry = nil

          expect { entry = create_specimen }.to change { specimens.count }.by(1)

          expect(entry._id).not_to be_nil
          expect(specimens.find(entry._id).name).to eq 'Created'
        end

        # Loading must not materialize fields the store never held: an update
        # of one field would write them back as stored data.
        it 'keeps a missing association missing through an unrelated update' do
          created = create_specimen
          entry   = another_specimens_repository.find(created._id)

          # Resolving the association must not materialize the key either.
          expect(entry.maker.name).to be_nil

          entry[:score] = 99
          specimens.update(entry)

          expect(specimens.exists?(_id: entry._id, 'maker.exists' => false)).to be(true)
        end

        describe 'the timestamps a write sets' do

          it 'stamps a creation once, in UTC milliseconds both stores keep' do
            moment   = Time.utc(2021, 3, 4, 5, 6, 7.123456789r)
            entry    = Timecop.freeze(moment) { create_specimen }
            reloaded = specimens.find(entry._id)

            expect(reloaded.created_at).to eq Time.utc(2021, 3, 4, 5, 6, 7.123r)
            expect(reloaded.created_at).to eq reloaded.updated_at
            expect(reloaded.created_at).to be_utc
            expect(reloaded.created_at).to eq entry.created_at
          end

          it 'normalizes the moments an import spells out to UTC milliseconds' do
            created = Time.new(2020, 1, 1, 14, 30, 0.123456789r, '+02:00')
            updated = Time.new(2020, 2, 2, 10, 0, 0.5r, '+02:00')

            entry    = create_specimen(created_at: created, updated_at: updated)
            reloaded = specimens.find(entry._id)

            expect(reloaded.created_at).to eq Time.utc(2020, 1, 1, 12, 30, 0.123r)
            expect(reloaded.created_at).to be_utc
            expect(reloaded.updated_at).to eq Time.utc(2020, 2, 2, 8, 0, 0.5r)
          end

          it 'keeps an explicit null a null' do
            entry    = create_specimen(created_at: nil, updated_at: nil)
            reloaded = specimens.find(entry._id)

            expect(reloaded.created_at).to be_nil
            expect(reloaded.updated_at).to be_nil
          end

          it 'owns updated_at on update, and leaves created_at alone' do
            entry   = create_specimen
            created = specimens.find(entry._id).created_at
            moment  = Time.utc(2022, 5, 6, 7, 8, 9.987654321r)

            entry[:updated_at] = Time.utc(2000, 1, 1)
            entry[:score]      = 5
            Timecop.freeze(moment) { specimens.update(entry) }

            reloaded = specimens.find(entry._id)

            expect(reloaded.updated_at).to eq Time.utc(2022, 5, 6, 7, 8, 9.987r)
            expect(reloaded.created_at).to eq created
          end

        end

        it 'links an association an entry never had' do
          created = create_specimen
          entry   = another_specimens_repository.find(created._id)

          entry[:maker_id] = makers.by_slug('maker-one')._id
          specimens.update(entry)

          expect(specimens.exists?(_id: entry._id, 'maker.exists' => true)).to be(true)
          expect(another_specimens_repository.find(created._id).maker.name).to eq 'Maker one'
        end

        # Updating a detached copy proves the write reaches the store instead
        # of mutating the object the previous read handed back.
        it 'makes an update visible to a later read' do
          entry    = create_specimen
          detached = entry.dup.tap { |copy| copy[:score] = 99 }

          specimens.update(detached)

          expect(specimens.find(entry._id).score).to eq 99
        end

        it "shows another instance's update to a later read" do
          repo    = specimens
          created = create_specimen(score: 5)

          expect(repo.find(created._id).score).to eq 5

          moved_on = another_specimens_repository
          moved_on.update(moved_on.find(created._id).tap { |stored| stored[:score] = 6 })

          expect(repo.find(created._id).score).to eq 6
        end

        it 'reports an update of an entry no longer in the store' do
          entry = create_specimen

          specimens.delete(entry)
          entry[:score] = 99

          expect { specimens.update(entry) }
            .to raise_error(Locomotive::Steam::Models::Repository::RecordNotFound)
        end

        it 'reports a delete of an entry no longer in the store' do
          entry = create_specimen

          specimens.delete(entry)

          expect { specimens.delete(entry) }
            .to raise_error(Locomotive::Steam::Models::Repository::RecordNotFound)
        end

        it 'accepts an idempotent update' do
          moment = Time.utc(2024, 1, 2, 3, 4, 5)
          entry  = Timecop.freeze(moment) { create_specimen }

          expect { Timecop.freeze(moment) { specimens.update(entry) } }.not_to raise_error
        end

        it 'removes an entry from later reads' do
          entry = create_specimen

          expect { specimens.delete(entry) }.to change { specimens.count }.by(-1)
          expect(specimens.find(entry._id)).to be_nil
        end

        # rank follows status, so a default must not stop at the first field
        # the attributes already carry.
        it 'fills the fields a new entry leaves out' do
          given = build_specimen(status: 'live')

          expect(build_specimen.status).to eq 'draft'
          expect(given.status).to eq 'live'
          expect(given.rank).to eq 7
        end

        it 'preserves an explicit null' do
          spelled = build_specimen(status: nil)

          expect(spelled.status).to be_nil
          expect(spelled.rank).to eq 7
        end

        it 'keeps a localized default as its content type spells it' do
          expect(build_specimen.blurb.translations).to eq('en' => 'Pending', 'fr' => 'En attente')
          expect(build_specimen(blurb: { en: 'given' }).blurb[:fr]).to be_nil
          expect(build_specimen(blurb: nil).blurb[:en]).to be_nil
        end

        # Both defaults name the second option, so picking any option is not
        # the same as picking the named one.
        it 'resolves a select default to the option id its own store issued' do
          silver = option_id(:tier, 'Silver')

          expect(build_specimen.visibility_id).to eq option_id(:visibility, 'private')
          expect(build_specimen.tier_id.translations).to eq('en' => silver, 'fr' => silver)
          expect(build_specimen(visibility_id: nil).visibility_id).to be_nil
        end

        it 'gives each entry its own copy of a default' do
          build_specimen.status << ' changed'

          expect(build_specimen.status).to eq 'draft'
        end

        it 'persists and reloads applied defaults' do
          stored = specimens.find(create_specimen(status: nil)._id)
          silver = option_id(:tier, 'Silver')

          expect(stored.status).to be_nil
          expect(stored.rank).to eq 7
          expect(stored.blurb.translations).to eq('en' => 'Pending', 'fr' => 'En attente')
          expect(stored.visibility_id).to eq option_id(:visibility, 'private')
          expect(stored.tier_id.translations).to eq('en' => silver, 'fr' => silver)
        end

        it 'creates an entry that leaves a non-localized select unset' do
          entry = specimens.build(name: 'Created without a category')

          written << entry
          specimens.create(entry)

          stored = specimens.find(entry._id)

          expect(stored.name).to eq 'Created without a category'
          expect(stored.category).to be_nil
          expect(stored.attributes).not_to have_key('category_id')
        end

        it 'keeps only the option an entry chose, not the label it reads as' do
          entry  = create_specimen(category_id: option_id(:category, 'alpha'))
          stored = specimens.find(entry._id)

          expect(stored.attributes['category_id']).to eq option_id(:category, 'alpha')
          expect(stored.category[:en]).to eq 'alpha'
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
