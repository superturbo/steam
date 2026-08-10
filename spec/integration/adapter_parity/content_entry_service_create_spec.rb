require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'
require_relative '../../support/adapter_parity_fixture'
require_relative '../../support/adapter_parity_context'

describe 'Adapter parity' do

  shared_examples_for 'the adapter parity dataset' do

    include_context 'adapter parity dataset access'

    describe 'the content entry service' do

      include_context 'adapter parity service access'

      describe 'writing' do

        include_context 'adapter parity service writing'

        it 'creates an entry a later read can see' do
          entry = nil

          expect { entry = service.create('submissions', valid) }
            .to change { service.all('submissions').size }.by(1)

          expect(entry['name']).to eq 'Ada'
          expect(entry['errors']).to be_blank
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

        it 'stores the value the field keeps, not the text the form sent' do
          created = readable_specimen(score: ' 12 ', price: '1.5', flag: '1',
                                      held_on: '2013-02-11', at: '2012-06-06T12:00:00Z')
          stored  = stored_specimen(created._id).attributes

          expect(stored.values_at(:score, :price, :flag)).to eq [12, 1.5, true]
          expect(stored[:held_on]).to eq Date.new(2013, 2, 11)
          expect(stored[:at].to_i).to eq Time.utc(2012, 6, 6, 12).to_i
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

        it 'stores text written in another encoding as the UTF-8 both stores read' do
          latin   = "caf\xE9".dup.force_encoding('ISO-8859-1')
          created = readable_specimen(status: latin, payload: { 'v' => latin })
          stored  = stored_specimen(created._id).attributes

          expect(stored['status'].encoding).to eq Encoding::UTF_8
          expect(stored['status'].bytes).to eq [99, 97, 102, 195, 169]
          expect(stored['payload']['v'].encoding).to eq Encoding::UTF_8
          expect(stored['payload']['v'].bytes).to eq [99, 97, 102, 195, 169]
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

        it 'writes the links a new entry declares' do
          entry = nil

          expect { entry = create_linked }.to change { service.all('specimens').size }.by(1)
          expect(links_of(entry._id)).to eq ['Maker one', ['Topic a']]
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
