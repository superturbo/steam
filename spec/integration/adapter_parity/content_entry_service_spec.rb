require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'
require_relative '../../support/adapter_parity_fixture'
require_relative '../../support/adapter_parity_context'

describe 'Adapter parity' do

  shared_examples_for 'the adapter parity dataset' do

    include_context 'adapter parity dataset access'

    describe 'the content entry service' do

      let(:entries) do
        Locomotive::Steam::ContentEntryRepository.new(
          adapter, site, AdapterParityFixture::LOCALE, type_repository)
      end

      let(:service) do
        Locomotive::Steam::ContentEntryService.new(
          type_repository, entries, AdapterParityFixture::LOCALE)
      end

      it 'lists what a type holds, and narrows it by conditions' do
        expect(service.all('specimens').size).to eq 6
        expect(service.all('specimens', flag: false).size).to eq 3
      end

      it 'lists as json' do
        entry = service.all('specimens', { flag: true }, true).first

        expect(entry.slice('name', 'score')).to eq('name' => 'Scalars', 'score' => 5)
      end

      # Filesystem ids are slugs, so only MongoDB reaches the fallback #find.
      it 'finds an entry by its slug and by the id its store issued' do
        scalars = service.find('specimens', 'scalars')

        expect(scalars.name).to eq 'Scalars'
        expect(service.find('specimens', scalars._id).name).to eq 'Scalars'
      end

      it 'finds an entry whose slug spells an object id' do
        expect(service.find('makers', '0123456789abcdef01234567').name).to eq 'Hex slug'
      end

      describe 'writing' do

        let(:valid)          { { name: 'Ada', email: 'ada@example.com', message: 'Hello' } }
        let(:writable_types) { %w(specimens submissions) }

        let(:original_ids) do
          writable_types.to_h { |type| [type, service.all(type).map(&:_id)] }
        end

        before { original_ids }

        # A failed create may leave a persisted entry, so remove everything
        # added here.
        after do
          writable_types.each do |type|
            service.all(type).each do |entry|
              service.delete(type, entry._id) unless original_ids.fetch(type).include?(entry._id)
            end
          end
        end

        it 'builds an entry without persisting it' do
          entry = service.build('submissions', valid)

          expect(entry['name']).to eq 'Ada'
          expect(entry['errors']).to be_blank
          expect(service.all('submissions').size).to eq 0
        end

        it 'creates an entry a later read can see' do
          entry = nil

          expect { entry = service.create('submissions', valid) }
            .to change { service.all('submissions').size }.by(1)

          expect(entry['name']).to eq 'Ada'
          expect(entry['errors']).to be_blank
        end

        it 'reports every missing required field at once, and persists nothing' do
          entry = nil

          expect { entry = service.create('submissions', {}, true) }
            .not_to change { service.all('submissions').size }

          expect(entry['errors']).to eq(
            'name'    => ["can't be blank"],
            'email'   => ["can't be blank"],
            'message' => ["can't be blank"]
          )
        end

        it 'updates an entry without adding one' do
          created = service.create('submissions', valid)
          updated = nil

          expect { updated = service.update('submissions', created._id, { name: 'Grace' }, true) }
            .not_to change { service.all('submissions').size }

          expect(updated).to be_a(Hash)
          expect(updated['name']).to eq 'Grace'
          expect(service.find('submissions', created._id).name).to eq 'Grace'
        end

        it 'leaves the store alone when an update does not validate' do
          updated = service.update('specimens', 'scalars', name: 'Arrays')

          expect(updated.errors.to_hash).to eq('name' => ['must be unique'])
          expect(service.find('specimens', 'scalars').name).to eq 'Scalars'
        end

        it 'returns validation errors without attaching them to the stored entry' do
          created = service.create('submissions', valid)
          updated = service.update('submissions', created._id, name: nil)

          expect(updated.errors.to_hash).to eq('name' => ["can't be blank"])
          expect(service.find('submissions', created._id).name).to eq 'Ada'
          expect(service.find('submissions', created._id).errors).to be_empty
        end

        it 'leaves the entry alone when the store refuses the write' do
          created = service.create('submissions', valid)

          allow(entries).to receive(:update).and_raise('the store refused')

          expect { service.update('submissions', created._id, name: 'Grace') }
            .to raise_error('the store refused')
          expect(service.find('submissions', created._id).name).to eq 'Ada'
        end

        def entries_of(type_slug)
          Locomotive::Steam::ContentEntryRepository.new(
            adapter, site, AdapterParityFixture::LOCALE, type_repository)
            .with(type_repository.by_slug(type_slug))
        end

        def create_linked
          service.create('specimens',
                         name: 'Linked',
                         category_id: option_id(:category, 'alpha'),
                         maker_id: entries_of('makers').by_slug('maker-one')._id,
                         topic_ids: [entries_of('topics').by_slug('topic-a')._id])
        end

        # Use a fresh mapper so cached entities cannot hide persisted state.
        def stored_specimen(id)
          entries_of('specimens').find(id)
        end

        def links_of(id)
          stored = stored_specimen(id)

          [stored.maker&.name, stored.topics.all.map(&:name)]
        end

        def service_in(locale)
          types = Locomotive::Steam::ContentTypeRepository.new(adapter, site, locale)

          Locomotive::Steam::ContentEntryService.new(
            types, Locomotive::Steam::ContentEntryRepository.new(adapter, site, locale, types), locale)
        end

        def localized_specimen
          service.create('specimens', name: 'Localized', category_id: option_id(:category, 'alpha'),
                                      topic_ids: [], title: { 'en' => 'Hello', 'fr' => 'Bonjour' })
        end

        it 'writes a lone value into the locale the entry is created in' do
          created = service.create('specimens', name: 'Lone', topic_ids: [],
                                                category_id: option_id(:category, 'alpha'),
                                                title: 'Hello')

          expect(entries_of('specimens').find(created._id).title.translations).to eq('en' => 'Hello')
        end

        it 'writes it into the locale that created it, not the site default' do
          created = service_in(:fr).create('specimens', name: 'Lone fr', topic_ids: [],
                                                        category_id: option_id(:category, 'alpha'),
                                                        title: 'Bonjour')

          expect(entries_of('specimens').find(created._id).title.translations).to eq('fr' => 'Bonjour')
        end

        it 'keeps a localized field localized through an update' do
          created = localized_specimen

          service.update('specimens', created._id, title: 'Only en now')

          expect(entries_of('specimens').find(created._id).title.translations)
            .to eq('en' => 'Only en now', 'fr' => 'Bonjour')
        end

        it 'writes a lone value into the locale being edited' do
          created = localized_specimen

          service_in(:fr).update('specimens', created._id, title: 'Salut')

          expect(entries_of('specimens').find(created._id).title.translations)
            .to eq('en' => 'Hello', 'fr' => 'Salut')
        end

        def readable_specimen(attributes)
          service.create('specimens', { name: 'Readable', topic_ids: [],
                                        category_id: option_id(:category, 'alpha') }.merge(attributes))
        end

        it 'stores the value the field keeps, not the text the form sent' do
          created = readable_specimen(score: ' 12 ', price: '1.5', flag: '1',
                                      held_on: '2013-02-11', at: '2012-06-06T12:00:00Z')
          stored  = stored_specimen(created._id).attributes

          expect(stored.values_at(:score, :price, :flag)).to eq [12, 1.5, true]
          expect(stored[:held_on]).to eq Date.new(2013, 2, 11)
          expect(stored[:at].to_i).to eq Time.utc(2012, 6, 6, 12).to_i
        end

        def ids_matching(conditions)
          entries_of('specimens').all(conditions).map(&:_id)
        end

        # A store that kept the text would still read back as a date; only a query
        # the store answers itself can tell what it holds.
        it 'stores a date the store can be queried by' do
          created = readable_specimen(held_on: '2013-02-11', at: '2012-06-06T12:00:00Z')

          expect(ids_matching(held_on: Date.new(2013, 2, 11))).to include created._id
          expect(ids_matching(at: Time.utc(2012, 6, 6, 12))).to include created._id
        end

        it 'stores one JSON object, whatever the caller spelled it as' do
          created = readable_specimen(payload: '{"a":[1,{"b":null}]}')

          expect(stored_specimen(created._id).attributes['payload']).to eq('a' => [1, { 'b' => nil }])
        end

        it 'writes a localized JSON object into the locale it was created in' do
          created = readable_specimen(notes: '{"note":"first"}')

          expect(stored_specimen(created._id).attributes['notes'].translations)
            .to eq('en' => { 'note' => 'first' })
        end

        it 'stores JSON nested as deep as a field reads it' do
          deep    = (1..97).inject('n' => 1) { |inner, _| { 'n' => inner } }
          created = readable_specimen(payload: deep, notes: { 'en' => deep })
          stored  = stored_specimen(created._id).attributes

          expect(stored['payload']).to eq deep
          expect(stored['notes'].translations).to eq('en' => deep)
        end

        it 'keeps the text inside JSON exactly as it was written' do
          created = readable_specimen(payload: '{"html":"<script>a < b & c</script>"}')

          expect(stored_specimen(created._id).attributes['payload'])
            .to eq('html' => '<script>a < b & c</script>')
        end

        it 'updates JSON a later read can see' do
          created = readable_specimen(payload: { 'a' => 1 })

          service.update('specimens', created._id, payload: '{"a":2}')

          expect(stored_specimen(created._id).attributes['payload']).to eq('a' => 2)
        end

        it 'leaves the stored JSON alone when an update does not validate' do
          created = readable_specimen(payload: { 'a' => 1 })
          updated = service.update('specimens', created._id, payload: '[1, 2, 3]')

          expect(updated.errors.to_hash).to eq('payload' => ['is invalid'])
          expect(stored_specimen(created._id).attributes['payload']).to eq('a' => 1)
        end

        it 'stores text written in another encoding as the UTF-8 both stores read' do
          latin   = "caf\xE9".dup.force_encoding('ISO-8859-1')
          created = readable_specimen(status: latin, payload: { 'v' => latin })
          stored  = stored_specimen(created._id).attributes

          expect(stored['status'].encoding).to eq Encoding::UTF_8
          expect(stored['status'].bytes).to eq [99, 97, 102, 195, 169]
          expect(stored['payload']['v'].encoding).to eq Encoding::UTF_8
          expect(stored['payload']['v'].bytes).to eq [99, 97, 102, 195, 169]
        end

        it 'refuses a plain text field the sanitizer could not read' do
          entry = nil

          expect { entry = readable_specimen(status: "caf\xFF".dup.force_encoding('UTF-8')) }
            .not_to change { service.all('specimens').size }

          expect(entry.errors.to_hash).to eq('status' => ['is invalid'])
        end

        it 'refuses text the sanitizer would have rewritten' do
          entry = readable_specimen(status: "caf\xE9".dup.force_encoding('ASCII-8BIT'))

          expect(entry.errors.to_hash).to eq('status' => ['is invalid'])
        end

        it 'refuses JSON holding text no encoding can read' do
          entry = nil

          expect { entry = readable_specimen(payload: { 'a' => %(x\xFF) }) }
            .not_to change { service.all('specimens').size }

          expect(entry.errors.to_hash).to eq('payload' => ['is invalid'])
        end

        it 'refuses JSON that is not an object' do
          entry = nil

          expect { entry = readable_specimen(payload: '[1, 2, 3]') }
            .not_to change { service.all('specimens').size }

          expect(entry.errors.to_hash).to eq('payload' => ['is invalid'])
        end

        it 'leaves a field the entry never filled out of the store' do
          created = readable_specimen(score: 12)

          service.update('specimens', created._id, score: 77)

          expect(stored_specimen(created._id).attributes).not_to have_key('price')
        end

        it 'refuses text the field cannot read, and writes nothing' do
          entry = nil

          expect { entry = readable_specimen(score: 'abc') }
            .not_to change { service.all('specimens').size }

          expect(entry.errors.to_hash).to eq('score' => ['is invalid'])
        end

        it 'refuses to write an entry no field can hold' do
          entry = entries_of('specimens').build(name: 'Refused', score: 'abc')

          expect { entries_of('specimens').create(entry) }
            .to raise_error(Locomotive::Steam::InvalidEntry) { |error| expect(error.entry).to be(entry) }
          expect(ids_matching(name: 'Refused')).to be_empty
        end

        it 'refuses to update a stored entry into one no field can hold' do
          created = readable_specimen(score: 12)
          stored  = stored_specimen(created._id)
          stored[:score] = 'abc'

          expect { entries_of('specimens').update(stored) }.to raise_error(Locomotive::Steam::InvalidEntry)
        end

        it 'leaves the store alone when an entry is changed in place and refused' do
          created = readable_specimen(score: 12)
          stored  = stored_specimen(created._id)
          stored[:score] = 'abc'

          expect { entries_of('specimens').update(stored) }.to raise_error(Locomotive::Steam::InvalidEntry)
          expect(stored_specimen(created._id).score).to eq 12
        end

        it 'leaves the entry the caller holds alone when a decorated update is refused' do
          created   = readable_specimen(score: 12)
          decorated = service.find('specimens', created._id)

          expect { service.update_decorated_entry(decorated, 'score' => 'abc') }
            .to raise_error(Locomotive::Steam::InvalidEntry)

          expect(decorated.score).to eq 12
          expect(stored_specimen(created._id).score).to eq 12
        end

        it 'writes a decorated update the caller can go on reading' do
          created   = readable_specimen(score: 12)
          decorated = service.find('specimens', created._id)

          service.update_decorated_entry(decorated, 'score' => 77)

          expect(decorated.score).to eq 77
          expect(stored_specimen(created._id).score).to eq 77
        end

        it 'reads an entry no one else is holding' do
          created = readable_specimen(score: 12)

          stored_specimen(created._id)[:score] = 99

          expect(stored_specimen(created._id).score).to eq 12
        end

        it 'stores its own copy of written values' do
          created = readable_specimen(score: 12, payload: { 'a' => 'one' }, labels: ['x'])

          created[:payload]['a'] << ' more'
          created[:labels] << 'y'

          stored = stored_specimen(created._id).attributes

          expect(stored['payload']).to eq('a' => 'one')
          expect(stored['labels']).to eq ['x']
        end

        it 'writes a decorated update of an entry that chose no option' do
          created   = service.create('specimens', name: 'No option', topic_ids: [])
          decorated = service.find('specimens', created._id)

          service.update_decorated_entry(decorated, 'score' => 77)

          expect(stored_specimen(created._id).score).to eq 77
        end

        it 'keeps a later assignment on the entry out of the store' do
          created   = readable_specimen(score: 12)
          decorated = service.find('specimens', created._id)

          service.update_decorated_entry(decorated, 'score' => 77)
          decorated.__getobj__[:score] = 'abc'

          expect(stored_specimen(created._id).score).to eq 77
        end

        it 'writes the links a new entry declares' do
          entry = nil

          expect { entry = create_linked }.to change { service.all('specimens').size }.by(1)
          expect(links_of(entry._id)).to eq ['Maker one', ['Topic a']]
        end

        it 'keeps them through an update of another field' do
          entry = create_linked

          service.update('specimens', entry._id, score: 77)

          expect(links_of(entry._id)).to eq ['Maker one', ['Topic a']]
        end

        it 'keeps them through a decorated update' do
          entry = create_linked

          service.update_decorated_entry(service.find('specimens', entry._id), 'score' => 77)

          expect(links_of(entry._id)).to eq ['Maker one', ['Topic a']]
        end

        it 'clears the links an update spells out' do
          entry = create_linked

          service.update('specimens', entry._id, maker_id: nil, topic_ids: [])

          expect(links_of(entry._id)).to eq [nil, []]
        end

        it 'creates an entry that leaves a many_to_many unset' do
          entry = service.create('specimens',
                                 name: 'Unlinked',
                                 category_id: option_id(:category, 'alpha'))

          stored = stored_specimen(entry._id)

          expect(entry['name']).to eq 'Unlinked'
          expect(entry['topic_ids']).to be_nil
          expect(stored.name).to eq 'Unlinked'
          expect(stored.attributes).not_to have_key('topic_ids')
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
