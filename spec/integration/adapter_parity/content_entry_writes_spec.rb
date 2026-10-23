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

        describe 'an association a write names by its target' do

          def topics_repository
            Locomotive::Steam::ContentEntryRepository.new(adapter, site, AdapterParityFixture::LOCALE, type_repository)
              .with(type_repository.by_slug('topics'))
          end

          def stored(created)
            another_specimens_repository.find(created._id)
          end

          it 'stores an assigned belongs_to target as its id' do
            created = create_specimen(maker_id: makers.by_slug('maker-one')._id)
            entry   = another_specimens_repository.find(created._id)

            entry[:maker] = makers.by_slug('maker-two')
            specimens.update(entry)

            expect([stored(created)[:maker_id], stored(created).maker.name]).to eq [makers.by_slug('maker-two')._id, 'Maker two']
          end

          it 'keeps an id set after the association was read' do
            created = create_specimen(maker_id: makers.by_slug('maker-two')._id)
            entry   = another_specimens_repository.find(created._id)

            entry.maker.name
            entry[:maker_id] = makers.by_slug('maker-one')._id
            specimens.update(entry)

            expect([stored(created)[:maker_id], stored(created).maker.name]).to eq [makers.by_slug('maker-one')._id, 'Maker one']
          end

          it 'reads the target a new id names after reading the old one' do
            entry = another_specimens_repository.find(create_specimen(maker_id: makers.by_slug('maker-two')._id)._id)

            entry.maker.name
            entry[:maker_id] = makers.by_slug('maker-one')._id

            expect(entry.maker.name).to eq 'Maker one'
          end

          it 'keeps an id set after the association read no target' do
            created = create_specimen(maker_id: nil)
            entry   = another_specimens_repository.find(created._id)

            expect(entry.maker.name).to be_nil
            entry[:maker_id] = makers.by_slug('maker-one')._id
            specimens.update(entry)

            expect(stored(created).maker.name).to eq 'Maker one'
          end

          it 'keeps the id of a target it could not read through a write of another field' do
            missing = filesystem? ? 'no-such-maker' : BSON::ObjectId.new
            created = create_specimen(maker_id: missing)
            entry   = another_specimens_repository.find(created._id)

            expect(entry.maker.name).to be_nil
            entry[:score] = 12
            specimens.update(entry)

            expect(stored(created)[:maker_id]).to eq missing
          end

          it 'stores the id assigned after a target' do
            created = create_specimen(maker_id: nil)
            entry   = another_specimens_repository.find(created._id)

            entry[:maker]    = makers.by_slug('maker-one')
            entry[:maker_id] = makers.by_slug('maker-two')._id
            specimens.update(entry)

            expect(stored(created)[:maker_id]).to eq makers.by_slug('maker-two')._id
          end

          it 'stores the target assigned after an id' do
            created = create_specimen(maker_id: nil)
            entry   = another_specimens_repository.find(created._id)

            entry[:maker_id] = makers.by_slug('maker-two')._id
            entry[:maker]    = makers.by_slug('maker-one')
            specimens.update(entry)

            expect(stored(created)[:maker_id]).to eq makers.by_slug('maker-one')._id
          end

          it 'stores the id a change gives after a target' do
            created = create_specimen(maker_id: nil)
            entry   = another_specimens_repository.find(created._id)

            entry.change(maker: makers.by_slug('maker-one'), maker_id: makers.by_slug('maker-two')._id)
            specimens.update(entry)

            expect(stored(created)[:maker_id]).to eq makers.by_slug('maker-two')._id
          end

          it 'stores the target a change gives after an id' do
            created = create_specimen(maker_id: nil)
            entry   = another_specimens_repository.find(created._id)

            entry.change(maker_id: makers.by_slug('maker-two')._id, maker: makers.by_slug('maker-one'))
            specimens.update(entry)

            expect(stored(created)[:maker_id]).to eq makers.by_slug('maker-one')._id
          end

          it 'clears the link when no target is assigned last' do
            created = create_specimen(maker_id: nil)
            entry   = another_specimens_repository.find(created._id)

            entry.maker.name
            entry[:maker_id] = makers.by_slug('maker-one')._id
            entry[:maker]    = nil
            specimens.update(entry)

            expect(stored(created)[:maker_id]).to be_nil
          end

          it 'stores the target it read, assigned again after another id' do
            created = create_specimen(maker_id: makers.by_slug('maker-two')._id)
            entry   = another_specimens_repository.find(created._id)
            entry.maker.name
            read = entry[:maker]

            entry[:maker_id] = makers.by_slug('maker-one')._id
            entry[:maker]    = read
            specimens.update(entry)

            expect(stored(created)[:maker_id]).to eq makers.by_slug('maker-two')._id
          end

          it 'keeps an assigned target through a second write' do
            created = create_specimen(maker_id: makers.by_slug('maker-one')._id)
            entry   = another_specimens_repository.find(created._id)

            entry[:maker] = makers.by_slug('maker-two')
            specimens.update(entry)
            entry[:score] = 12
            specimens.update(entry)

            expect(stored(created)[:maker_id]).to eq makers.by_slug('maker-two')._id
          end

          it 'reads an assigned target by its id before the write' do
            entry = another_specimens_repository.find(create_specimen(maker_id: nil)._id)

            entry[:maker] = makers.by_slug('maker-two')

            expect(entry[:maker_id]).to eq makers.by_slug('maker-two')._id
          end

          it 'reads assigned many_to_many targets by their ids before the write' do
            entry   = another_specimens_repository.find(create_specimen(topic_ids: [])._id)
            topic_b = topics_repository.by_slug('topic-b')

            entry[:topics] = [topic_b]

            expect(entry[:topic_ids]).to eq [topic_b._id]
          end

          it 'reads a renamed target through a link assigned before the entry is created' do
            topics = topics_repository
            fresh  = topics.create(topics.build(name: 'Fresh topic', _slug: 'fresh-topic'))
            entity = build_specimen(name: 'Linked to fresh')
            entity[:topics] = [fresh]
            created = specimens.create(entity).tap { |entry| written << entry }

            renamed = topics.find(fresh._id)
            renamed[:name] = 'Renamed topic'
            topics.update(renamed)

            expect(stored(created).topics.all.map(&:name)).to eq ['Renamed topic']
          ensure
            topics.delete(topics.find(fresh._id)) if fresh&._id && topics.find(fresh._id)
          end

          it 'leaves the target the caller assigned in place' do
            created = create_specimen(maker_id: makers.by_slug('maker-one')._id)
            entry   = another_specimens_repository.find(created._id)
            two     = makers.by_slug('maker-two')

            entry[:maker] = two
            specimens.update(entry)

            expect(entry[:maker].equal?(two)).to be true
          end

          it 'stores assigned many_to_many targets as their ids' do
            created = create_specimen(topic_ids: [])
            entry   = another_specimens_repository.find(created._id)
            topic_b = topics_repository.by_slug('topic-b')

            entry[:topics] = [topic_b]
            specimens.update(entry)

            expect([stored(created)[:topic_ids], stored(created).topics.all.map(&:name)]).to eq [[topic_b._id], ['Topic b']]
          end

          it 'reads the targets new ids name after other targets were assigned' do
            entry  = another_specimens_repository.find(create_specimen(topic_ids: [])._id)
            topics = topics_repository

            entry[:topics]    = [topics.by_slug('topic-a')]
            entry[:topic_ids] = [topics.by_slug('topic-b')._id]

            expect(entry.topics.all.map(&:name)).to eq ['Topic b']
          end

          it 'stores the ids a change gives after targets' do
            created = create_specimen(topic_ids: [])
            entry   = another_specimens_repository.find(created._id)
            topics  = topics_repository

            entry.change(topics: [topics.by_slug('topic-a')], topic_ids: [topics.by_slug('topic-b')._id])
            specimens.update(entry)

            expect(stored(created)[:topic_ids]).to eq [topics.by_slug('topic-b')._id]
          end

          it 'stores the targets a change gives after ids' do
            created = create_specimen(topic_ids: [])
            entry   = another_specimens_repository.find(created._id)
            topics  = topics_repository

            entry.change(topic_ids: [topics.by_slug('topic-b')._id], topics: [topics.by_slug('topic-a')])
            specimens.update(entry)

            expect(stored(created)[:topic_ids]).to eq [topics.by_slug('topic-a')._id]
          end

          it 'stores many_to_many targets assigned before the entry is created as their ids' do
            topic_b = topics_repository.by_slug('topic-b')
            entity  = build_specimen(name: 'Assigned topics')
            entity[:topics] = [topic_b]
            created = specimens.create(entity).tap { |entry| written << entry }

            expect(stored(created)[:topic_ids]).to eq [topic_b._id]
          end

          it 'stores a target assigned before the entry is created as its id' do
            entity = build_specimen(name: 'Assigned')
            entity[:maker] = makers.by_slug('maker-two')
            created = specimens.create(entity).tap { |entry| written << entry }

            expect([stored(created)[:maker_id], stored(created).maker.name]).to eq [makers.by_slug('maker-two')._id, 'Maker two']
          end

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
