require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'
require_relative '../../support/adapter_parity_fixture'
require_relative '../../support/adapter_parity_context'

describe 'Adapter parity' do

  shared_examples_for 'the adapter parity dataset' do |store|

    include_context 'adapter parity dataset access'

    describe 'the content entry service' do

      include_context 'adapter parity service access'

      describe 'writing' do

        include_context 'adapter parity service writing'

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

        it 'leaves the stored JSON alone when an update does not validate' do
          created = readable_specimen(payload: { 'a' => 1 })
          updated = service.update('specimens', created._id, payload: '[1, 2, 3]')

          expect(updated.errors.to_hash).to eq('payload' => ['is invalid'])
          expect(stored_specimen(created._id).attributes['payload']).to eq('a' => 1)
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

        it 'leaves the entry the caller holds alone when a decorated update names an unknown option' do
          created   = readable_specimen(category_id: option_id(:category, 'alpha'))
          decorated = service.find('specimens', created._id)

          expect { service.update_decorated_entry(decorated, 'category_id' => 'bogus') }
            .to raise_error(Locomotive::Steam::InvalidEntry)

          expect(decorated.category).to eq 'alpha'
          expect(stored_specimen(created._id).attributes['category_id']).to eq option_id(:category, 'alpha')
        end

        describe 'a unique field' do

          let(:writable_types) { %w(specimens submissions tickets vouchers) }
          let(:taken)          { ['must be unique'] }

          def ticket(attributes = {})
            @serial = (@serial || 0) + 1
            service.create('tickets', { title: 'Ticket', serial: "S#{@serial}" }.merge(attributes), true)
          end

          def raw_entries
            AdapterParityFixture.mongodb_client[AdapterParityFixture::MongoDBDocuments::CONTENT_ENTRIES_COLLECTION]
          end

          it 'refuses a value another entry of its type holds' do
            ticket(code: 7)

            expect(ticket(code: 7)['errors']).to eq('code' => taken)
          end

          it 'takes a value an entry of another type holds' do
            service.create('vouchers', { title: 'Voucher', code: 7 }, true)

            expect(ticket(code: 7)['errors']).to be_blank
          end

          it 'keeps its own value through an update' do
            created = ticket(code: 7)

            expect(service.update('tickets', created['_id'], { title: 'Renamed', code: 7 }, true)['errors']).to be_blank
          end

          it 'counts a hidden entry' do
            hidden     = ticket(code: 7)
            repository = entries_of('tickets')
            repository.find(hidden['_id']).tap { |entry| entry[:_visible] = false; repository.update(entry) }

            expect(ticket(code: 7)['errors']).to eq('code' => taken)
          end

          [nil, ''].each do |blank|
            it "leaves #{blank.inspect} out when the field is optional" do
              ticket(reference: blank)

              expect(ticket(reference: blank)['errors']).to be_blank
            end
          end

          it 'reports a required field left blank as missing only' do
            repository = entries_of('tickets')
            repository.adapter.create(repository.send(:mapper), repository.scope, repository.build(title: 'Stored', serial: ''))

            expect(service.create('tickets', { title: 'Ticket', serial: '' }, true)['errors']).to eq('serial' => ["can't be blank"])
          end

          it 'checks zero and false as values' do
            ticket(code: 0, active: false)

            expect(ticket(code: 0, active: false)['errors']).to eq('code' => taken, 'active' => taken)
          end

          it 'compares a localized value in the locale that writes' do
            ticket(heading: 'Open')

            expect(ticket(heading: 'Open')['errors']).to eq('heading' => taken)
          end

          it 'compares every locale a write stores' do
            ticket(heading: { 'en' => 'First', 'fr' => 'Commun' })

            expect(ticket(heading: { 'en' => 'Second', 'fr' => 'Commun' })['errors']).to eq('heading' => taken)
          end

          it 'compares every locale an update stores' do
            ticket(heading: { 'en' => 'First', 'fr' => 'Commun' })
            created = ticket(heading: { 'en' => 'Second' })

            updated = service.update('tickets', created['_id'], { heading: { 'en' => 'Second', 'fr' => 'Commun' } }, true)

            expect(updated['errors']).to eq('heading' => taken)
          end

          # A localized field stored as one value reads in every locale.
          def store_one_heading(id, value)
            if filesystem?
              repository = entries_of('tickets')
              entry      = repository.all(_id: id, _visible: nil).first
              entry[:heading] = Locomotive::Steam::Models::I18nField.new(:heading, value)
              repository.adapter.update(repository.send(:mapper), repository.scope, entry)
            else
              raw_entries.update_one({ '_id' => BSON::ObjectId.from_string(id.to_s) }, { '$set' => { 'heading' => value } })
            end
          end

          it 'compares a value the store holds for every locale' do
            ticket(heading: { 'en' => 'Shared' })
            legacy = ticket(heading: { 'en' => 'Other' })
            store_one_heading(legacy['_id'], 'Shared')

            expect(entries_of('tickets').all(_id: legacy['_id'], _visible: nil).first.heading.translations).to be_empty
            expect(service.update('tickets', legacy['_id'], { title: 'Renamed' }, true)['errors']).to eq('heading' => taken)
          end

          it 'does not add queries for unconfigured locales' do
            queries = 0
            allow(adapter).to receive(:query).and_wrap_original do |original, *args, &block|
              queries += 1
              original.call(*args, &block)
            end
            count = ->(heading) { queries.tap { ticket(heading: heading) }.then { |before| queries - before } }
            count.({ 'en' => 'Warm' })

            named = { 'en' => 'Two', 'fr' => 'Deux' }

            expect(count.(named.merge((1..20).to_h { |i| ["x#{i}", "v#{i}"] }))).to eq count.({ 'en' => 'One', 'fr' => 'Un' })
          end

          it 'takes one text in two locales' do
            ticket(heading: { 'en' => 'Commun' })

            expect(ticket(heading: { 'fr' => 'Commun' })['errors']).to be_blank
          end

          it 'compares a date' do
            ticket(day: '2026-10-22')

            expect(ticket(day: '2026-10-22')['errors']).to eq('day' => taken)
          end

          it 'compares a select by the option it stores' do
            ticket(category: 'alpha')

            expect(ticket(category: 'alpha')['errors']).to eq('category' => taken)
            expect(ticket(category: 'beta')['errors']).to be_blank
          end

          it 'compares a belongs_to by the entry it links' do
            ticket(maker: 'maker-one')

            expect(ticket(maker: 'maker-one')['errors']).to eq('maker' => taken)
            expect(ticket(maker: 'maker-two')['errors']).to be_blank
          end

          # Only MongoDB keeps several sites, and schemas no loader checked, in one store.
          if store == :mongodb
            it 'takes a value an entry of another site holds' do
              moved = BSON::ObjectId.from_string(ticket(code: 7)['_id'].to_s)
              raw_entries.update_one({ '_id' => moved }, { '$set' => { 'site_id' => BSON::ObjectId.new } })

              expect(ticket(code: 7)['errors']).to be_blank
            ensure
              raw_entries.delete_one('_id' => moved) if moved
            end

            it 'refuses every write of a type whose stored schema declares a unique field it cannot honor' do
              types   = AdapterParityFixture.mongodb_client[AdapterParityFixture::MongoDBDocuments::CONTENT_TYPES_COLLECTION]
              labels  = ->(unique) { types.update_one({ 'slug' => 'specimens', 'site_id' => AdapterParityFixture::SITE_ID },
                                                      { '$set' => { 'entries_custom_fields.$[field].unique' => unique } },
                                                      array_filters: [{ 'field.name' => 'labels' }]) }
              created = readable_specimen(score: 12)
              refused = [Locomotive::Steam::UnsupportedSchemaError, /specimens, field labels: uniqueness is not supported for a tags field/]
              labels.(true)

              decorated = service.find('specimens', created._id)

              expect { service.update_decorated_entry(decorated, 'score' => 77) }.to raise_error(*refused)
              expect { readable_specimen(name: 'Refused') }.to raise_error(*refused)
              expect(stored_specimen(created._id).score).to eq 12

              service.delete('specimens', created._id)
              expect(stored_specimen(created._id)).to be_nil
            ensure
              labels&.(false)
            end
          end

        end

      end

    end

  end

  context 'MongoDB' do

    before(:all) { AdapterParityFixture.seed_mongodb! }
    after(:all)  { AdapterParityFixture.cleanup! }

    it_should_behave_like 'the adapter parity dataset', :mongodb do
      let(:adapter)  { AdapterParityFixture.mongodb_adapter }

      def filesystem?; false; end
    end

  end

  context 'Filesystem' do

    it_should_behave_like 'the adapter parity dataset', :filesystem do
      let(:adapter) { AdapterParityFixture.filesystem_adapter }

      def filesystem?; true; end
    end

  end

end
