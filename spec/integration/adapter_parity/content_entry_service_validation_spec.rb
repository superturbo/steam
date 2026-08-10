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
