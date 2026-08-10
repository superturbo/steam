require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'
require_relative '../../support/adapter_parity_fixture'
require_relative '../../support/adapter_parity_context'

describe 'Adapter parity' do

  shared_examples_for 'the adapter parity dataset' do

    include_context 'adapter parity dataset access'

    describe 'the content entry repository' do

      def specimens(locale = AdapterParityFixture::LOCALE)
        types = Locomotive::Steam::ContentTypeRepository.new(adapter, site, locale)

        Locomotive::Steam::ContentEntryRepository.new(adapter, site, locale, types)
          .with(types.by_slug('specimens'))
      end

      it 'counts what it holds' do
        expect(specimens.count).to eq 6
      end

      it 'finds one entry by its slug' do
        expect(specimens.by_slug('scalars').name).to eq 'Scalars'
      end

      def makers
        types = Locomotive::Steam::ContentTypeRepository.new(adapter, site, AdapterParityFixture::LOCALE)

        Locomotive::Steam::ContentEntryRepository.new(adapter, site, AdapterParityFixture::LOCALE, types)
          .with(types.by_slug('makers'))
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

      it 'reads the ends of its own order' do
        expect(specimens.first.name).to eq 'All missing'
        expect(specimens.last.name).to eq 'Zero'
      end

      it 'answers whether anything matches a condition' do
        expect(specimens.exists?(flag: true)).to be(true)
      end

      it 'reads the first entry matching a condition' do
        expect(specimens.first(flag: true).name).to eq 'Scalars'
      end

      it 'walks to the neighbours of an entry in that order' do
        embedded = specimens.by_slug('embedded')

        expect(specimens.next(embedded).name).to eq 'Explicit nils'
        expect(specimens.previous(embedded).name).to eq 'Arrays'
      end

      # Prologue and Epilogue have no part at all, Middle and Opening share
      # one, and en and fr disagree about where Finale sits.
      describe 'navigating a key with ties and nulls' do

        def entries_of(slug, locale = AdapterParityFixture::LOCALE)
          types = Locomotive::Steam::ContentTypeRepository.new(adapter, site, locale)

          Locomotive::Steam::ContentEntryRepository.new(adapter, site, locale, types)
            .with(types.by_slug(slug))
        end

        def order_of(slug, locale = AdapterParityFixture::LOCALE)
          entries_of(slug, locale).all.map { |entry| entry._slug[locale] }
        end

        def walk(step, slug, locale)
          repository = entries_of(slug, locale)

          order_of(slug, locale).map do |current|
            neighbour = repository.public_send(step, repository.by_slug(current))

            neighbour && neighbour._slug[locale]
          end
        end

        it 'reads nulls first, then the key, then the slug' do
          expect(order_of('chapters')).to eq %w(epilogue prologue finale middle opening)
          expect(order_of('chapters', :fr)).to eq %w(epilogue prologue middle finale opening)
          expect(order_of('reverse_chapters')).to eq %w(middle opening finale epilogue prologue)
          expect(order_of('reverse_chapters', :fr)).to eq %w(opening finale middle epilogue prologue)
        end

        it 'steps through that order one entry at a time' do
          [['chapters', :en], ['chapters', :fr],
           ['reverse_chapters', :en], ['reverse_chapters', :fr]].each do |slug, locale|
            order = order_of(slug, locale)

            expect(walk(:next, slug, locale)).to eq [*order.drop(1), nil]
            expect(walk(:previous, slug, locale)).to eq [nil, *order[0..-2]]
          end
        end

        # A slug-ordered type needs no separate tie-breaker.
        it 'navigates a type ordered by the slug itself' do
          topics = entries_of('topics')

          expect(topics.next(topics.by_slug('topic-a'))._slug[:en]).to eq 'topic-b'
          expect(topics.previous(topics.by_slug('topic-b'))._slug[:en]).to eq 'topic-a'
          expect(topics.next(topics.by_slug('topic-b'))).to be_nil
        end

      end

      it 'orders by a field' do
        expect(slugs(order_by: 'name')).to eq %w(all-missing arrays embedded explicit-nils scalars zero)
      end

      it 'orders the rows with no number after the ones with zero' do
        expect(slugs(order_by: 'score.desc, name'))
          .to eq %w(arrays embedded scalars zero all-missing explicit-nils)
      end

      # Embedded and Scalars both have score 5.
      it 'breaks a tie by slug, ascending and descending alike' do
        expect(slugs(order_by: 'score'))
          .to eq %w(all-missing explicit-nils zero embedded scalars arrays)
        expect(slugs(order_by: 'score.desc'))
          .to eq %w(arrays embedded scalars zero all-missing explicit-nils)
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

      it 'filters and orders by a date' do
        expect(slugs('held_on.lte' => Date.new(2020, 1, 1), order_by: 'held_on desc'))
          .to eq %w(arrays scalars)
      end

      describe 'writing' do

        def another_specimens_repository
          Locomotive::Steam::ContentEntryRepository.new(
            adapter, site, AdapterParityFixture::LOCALE, type_repository)
            .with(type_repository.by_slug('specimens'))
        end

        def build_specimen(attributes = {})
          specimens.build({ name: 'Created', score: 41,
                            category_id: option_id(:category, 'alpha') }.merge(attributes))
        end

        # Only Filesystem sanitizes a new entry into a slug, so reads here go
        # through the id both stores do issue.
        def create_specimen(attributes = {})
          specimens.create(build_specimen(attributes)).tap { |entry| written << entry }
        end

        let(:written) { [] }

        after do
          written.each { |entry| specimens.delete(entry) if entry._id && specimens.find(entry._id) }
        end

        it 'adds an entry a later read can see' do
          entry = nil

          expect { entry = create_specimen }.to change { specimens.count }.by(1)

          expect(entry._id).not_to be_nil
          expect(specimens.find(entry._id).name).to eq 'Created'
        end

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

        # Seed a value that predates repository validation.
        def store_specimen(attributes = {})
          build_specimen(attributes).tap do |entity|
            specimens.adapter.create(specimens.send(:mapper), specimens.scope, entity)
            written << entity
          end
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

        # Updating a detached copy proves the write reaches the store instead
        # of mutating the object the previous read handed back.
        it 'makes an update visible to a later read' do
          entry    = create_specimen
          detached = entry.dup.tap { |copy| copy[:score] = 99 }

          specimens.update(detached)

          expect(specimens.find(entry._id).score).to eq 99
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
