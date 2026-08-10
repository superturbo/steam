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

        it 'updates an entry without adding one' do
          created = service.create('submissions', valid)
          updated = nil

          expect { updated = service.update('submissions', created._id, { name: 'Grace' }, true) }
            .not_to change { service.all('submissions').size }

          expect(updated).to be_a(Hash)
          expect(updated['name']).to eq 'Grace'
          expect(service.find('submissions', created._id).name).to eq 'Grace'
        end

        it 'leaves the entry alone when the store refuses the write' do
          created = service.create('submissions', valid)

          allow(entries).to receive(:update).and_raise('the store refused')

          expect { service.update('submissions', created._id, name: 'Grace') }
            .to raise_error('the store refused')
          expect(service.find('submissions', created._id).name).to eq 'Ada'
        end

        it 'leaves a field the entry never filled out of the store' do
          created = readable_specimen(score: 12)

          service.update('specimens', created._id, score: 77)

          expect(stored_specimen(created._id).attributes).not_to have_key('price')
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

        it 'updates JSON a later read can see' do
          created = readable_specimen(payload: { 'a' => 1 })

          service.update('specimens', created._id, payload: '{"a":2}')

          expect(stored_specimen(created._id).attributes['payload']).to eq('a' => 2)
        end

        it 'writes a decorated update the caller can go on reading' do
          created   = readable_specimen(score: 12)
          decorated = service.find('specimens', created._id)

          service.update_decorated_entry(decorated, 'score' => 77)

          expect(decorated.score).to eq 77
          expect(stored_specimen(created._id).score).to eq 77
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
