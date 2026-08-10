require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'
require_relative '../../support/adapter_parity_fixture'
require_relative '../../support/adapter_parity_context'

describe 'Adapter parity' do

  shared_examples_for 'the adapter parity dataset' do

    include_context 'adapter parity dataset access'

    # A Wagon file spells every value as text; an Engine document holds it typed.
    describe 'a value spelled as text' do

      def spelled
        types = Locomotive::Steam::ContentTypeRepository.new(adapter, site, AdapterParityFixture::LOCALE)

        Locomotive::Steam::ContentEntryRepository.new(adapter, site, AdapterParityFixture::LOCALE, types)
          .with(types.by_slug('quoted')).all.first
      end

      it 'reaches both stores as the value its field keeps' do
        attributes = spelled.attributes

        expect(attributes.values_at(:score, :price, :flag)).to eq [7, 1.5, true]
        expect(attributes[:held_on]).to eq Date.new(2014, 3, 9)
        expect(attributes[:at]).to eq Time.utc(2019, 9, 10)
        expect(attributes[:payload]).to eq('a' => [1, { 'b' => nil }])
      end

      it 'reads out of both stores as the value its field keeps' do
        entry = spelled

        expect(entry.score).to eql 7
        expect(entry.price).to eql 1.5
        expect(entry.flag).to eq true
        expect(entry.name).to eq 'Spelled'
        expect(entry.held_on).to eql Date.new(2014, 3, 9)
        expect(entry.at).to eql Time.utc(2019, 9, 10)
        expect(entry.payload).to eq('a' => [1, { 'b' => nil }])
        expect(entry.title.translations).to eq('en' => ' Spelled en ', 'fr' => ' Spelled fr ')
        expect(entry.published.translations).to eq('en' => true, 'fr' => false)
      end

      # The store answers the query itself, before an entry is ever read.
      it 'is found by the value its field keeps' do
        types = Locomotive::Steam::ContentTypeRepository.new(adapter, site, AdapterParityFixture::LOCALE)
        found = Locomotive::Steam::ContentEntryRepository.new(adapter, site, AdapterParityFixture::LOCALE, types)
                  .with(types.by_slug('quoted')).all(score: 7, flag: true)

        expect(found.map(&:name)).to eq %w(Spelled)
      end

      it 'reaches them the same way in every locale' do
        attributes = spelled.attributes

        expect(attributes[:title].translations).to eq('en' => ' Spelled en ', 'fr' => ' Spelled fr ')
        expect(attributes[:published].translations).to eq('en' => true, 'fr' => false)
      end

    end

    it 'holds the same rows in both stores' do
      expect(slugs({})).to match_array %w(all-missing arrays embedded explicit-nils scalars zero)
    end

    # Row parity cannot expose differences in materialized values.
    describe 'the values read back' do

      def maker(slug)
        repository = Locomotive::Steam::ContentEntryRepository.new(
          adapter, site, AdapterParityFixture::LOCALE, type_repository)

        repository.with(type_repository.by_slug('makers')).all.detect do |candidate|
          candidate._slug[AdapterParityFixture::LOCALE] == slug
        end
      end

      def entry(slug)
        repository = Locomotive::Steam::ContentEntryRepository.new(
          adapter, site, AdapterParityFixture::LOCALE, type_repository)

        repository.with(type_repository.by_slug('specimens')).all.detect do |candidate|
          candidate._slug[AdapterParityFixture::LOCALE] == slug
        end
      end

      it 'reads a localized JSON object identically' do
        expect(entry('scalars').notes.translations)
          .to eq('en' => { 'note' => 'first' }, 'fr' => { 'note' => 'premiere' })
      end

      it 'reads a scalar, a boolean, a date and a date-time identically' do
        expect(entry('scalars').score).to eq 5
        expect(entry('scalars').flag).to eq true
        expect(entry('zero').score).to eq 0
        expect(entry('scalars').at.to_i).to eq Time.utc(2012, 6, 6, 12, 0, 0).to_i
        expect(entry('scalars').held_on).to eq Date.new(2013, 2, 11)
      end

      def slugs_of(collection)
        collection.map { |target| target._slug[AdapterParityFixture::LOCALE] }
      end

      it 'reads a belongs_to as the target slug, and nil when unlinked' do
        expect(entry('scalars').maker._slug[AdapterParityFixture::LOCALE]).to eq 'maker-one'
        expect(entry('embedded').maker._slug[AdapterParityFixture::LOCALE]).to eq 'maker-two'
        expect(entry('zero').maker._slug).to be_nil
      end

      it 'reads the inverse has_many in the stated order' do
        expect(slugs_of(maker('maker-one').specimens.all)).to eq %w(scalars arrays)
        expect(slugs_of(maker('maker-two').specimens.all)).to eq %w(embedded)
      end

      it 'reads a many_to_many in the stated order, and empty when unlinked' do
        expect(slugs_of(entry('scalars').topics.all)).to eq %w(topic-a topic-b)
        expect(slugs_of(entry('arrays').topics.all)).to eq %w(topic-b)
        expect(entry('zero').topics.all).to eq []
      end

      it 'never fills a stored field from its content type default' do
        expect(entry('all-missing').status).to be_nil
        expect(entry('explicit-nils').status).to be_nil
        expect(entry('scalars').status).to eq 'published'
        expect(entry('scalars').rank).to be_nil
        expect(entry('scalars').blurb).to be_nil
        expect(entry('explicit-nils').visibility_id).to be_nil
      end

      it 'reads a date and a date-time as the same value from either store' do
        stored = entry('scalars')

        expect(stored[:held_on]).to eql Date.new(2013, 2, 11)
        expect(stored[:at]).to eql Time.utc(2012, 6, 6, 12)
      end

      it 'leaves a field the store never wrote missing' do
        expect(entry('all-missing').attributes).not_to have_key('held_on')
        expect(entry('explicit-nils').attributes['at']).to be_nil
      end

      it 'keeps missing and null numeric values nil' do
        expect(entry('explicit-nils').score).to be_nil
        expect(entry('all-missing').score).to be_nil
        expect(entry('zero').price).to be_nil
      end

      # Translation presence and effective value are verified separately.
      it 'keeps a missing locale distinct from an explicitly null one' do
        expect(entry('arrays').title.translations.key?('fr')).to eq false
        expect(entry('embedded').title.translations.key?('fr')).to eq true
        expect(entry('embedded').title.translations['fr']).to be_nil
      end

      it 'reads the effective localized value of a present locale' do
        expect(entry('scalars').title[:en]).to eq 'Scalars en'
        expect(entry('scalars').title[:fr]).to eq 'Scalars fr'
      end

      # A localized select carries both its own name and the id an entry stores.
      it 'leaves an untranslated select and metadata locale absent' do
        expect(entry('embedded').tier.translations.keys).to eq %w(en)
        expect(entry('embedded').tier_id.translations.keys).to eq %w(en)
        expect(entry('embedded').seo_title.translations.keys).to eq %w(en)
      end

      it 'reads no effective value for a missing or explicitly null locale' do
        expect(entry('arrays').title[:fr]).to be_nil
        expect(entry('embedded').title[:fr]).to be_nil
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

    # The seed mirrors Filesystem: an unlinked document carries no inverse
    # position and no foreign key. The raw document is the proof — an entity
    # could hide a wrong stored form.
    describe 'what the store holds for an unlinked belongs_to' do

      let(:adapter) { AdapterParityFixture.mongodb_adapter }

      def zero_document
        AdapterParityFixture.mongodb_client[
          AdapterParityFixture::MongoDBDocuments::CONTENT_ENTRIES_COLLECTION]
          .find('_id' => AdapterParityFixture::WagonSite.entry_id('specimens', 'zero')).first
      end

      it 'holds neither the foreign key nor the inverse position' do
        document = zero_document

        expect(document.key?('maker_id')).to be false
        expect(document.key?('position_in_maker')).to be false
        expect(document.key?('title')).to be false
      end

      it 'still holds neither after an unrelated update' do
        site    = Locomotive::Steam::SiteRepository.new(adapter).by_handle_or_domain('adapter-parity', nil)
        types   = Locomotive::Steam::ContentTypeRepository.new(adapter, site, AdapterParityFixture::LOCALE)
        entries = Locomotive::Steam::ContentEntryRepository.new(adapter, site, AdapterParityFixture::LOCALE, types)
                    .with(types.by_slug('specimens'))

        entry = entries.by_slug('zero')
        entry[:score] = 0 # the stored value, so the fixture stays as seeded

        entries.update(entry)

        document = zero_document

        expect(document.key?('maker_id')).to be false
        expect(document.key?('position_in_maker')).to be false
        expect(document.key?('title')).to be false
      end

    end

    # Filesystem rejects invalid types while loading, so this case is MongoDB-only.
    describe 'a value the store holds as text' do

      let(:adapter) { AdapterParityFixture.mongodb_adapter }
      let(:site)    { Locomotive::Steam::SiteRepository.new(adapter).by_handle_or_domain('adapter-parity', nil) }
      let(:types)   { Locomotive::Steam::ContentTypeRepository.new(adapter, site, AdapterParityFixture::LOCALE) }

      def spelled
        Locomotive::Steam::ContentEntryRepository.new(adapter, site, AdapterParityFixture::LOCALE, types)
          .with(types.by_slug('quoted')).all.first
      end

      { 'score'   => ['7',                    'integer', 7],
        'held_on' => ['2014-03-09',           'date',    Date.new(2014, 3, 9)],
        'payload' => ['{"a":[1,{"b":null}]}', 'json',    { 'a' => [1, { 'b' => nil }] }]
      }.each do |name, (held, expected_type, seeded)|

        context "a #{expected_type} field" do

          around do |example|
            entries  = AdapterParityFixture.mongodb_client[
              AdapterParityFixture::MongoDBDocuments::CONTENT_ENTRIES_COLLECTION]
            selector = { '_id' => AdapterParityFixture::WagonSite.entry_id('quoted', 'spelled') }

            entries.update_one(selector, '$set' => { name => held })
            example.run
          ensure
            entries.update_one(selector, '$set' => { name => seeded })
          end

          it 'returns nil and reports the invalid stored type' do
            events   = []
            callback = ->(*, payload) { events << payload }

            ActiveSupport::Notifications.subscribed(callback, 'steam.entries.unread_value') do
              expect(spelled.send(name)).to be_nil
            end

            expect(events.map { |e| e.values_at(:content_type, :field, :expected_type, :actual_type, :reason) })
              .to eq [['quoted', name, expected_type, 'String', 'wrong_stored_type']]
          end

        end
      end

    end
  end

  context 'Filesystem' do

    it_should_behave_like 'the adapter parity dataset' do
      let(:adapter) { AdapterParityFixture.filesystem_adapter }

      def filesystem?; true; end
    end

  end

end
