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

      describe 'writing a password' do

        include_context 'adapter parity service writing'

        def create_with(input)
          service.create('submissions', valid.merge(input), true)
        end

        def raw_entries
          AdapterParityFixture.mongodb_client[AdapterParityFixture::MongoDBDocuments::CONTENT_ENTRIES_COLLECTION]
        end

        # What the store holds, whatever the entry reads back.
        def stored(id)
          if filesystem?
            entries_of('submissions').find(id).attributes.to_h.transform_keys(&:to_s)
          else
            raw_entries.find(_id: BSON::ObjectId.from_string(id.to_s)).first.to_h
          end
        end

        def stored_password?(id, password)
          BCrypt::Password.new(stored(id)['secret_hash']).is_password?(password)
        end

        def stored_count
          service.all('submissions', _visible: nil).size
        end

        def refuses(input, field, message = 'is invalid')
          created = nil

          expect { created = create_with(input) }.not_to change { stored_count }

          expect(created['errors'][field]).to eq [message]
        end

        it 'stores a password as its hash, never as text' do
          created = create_with(secret: 'easyone', secret_confirmation: 'easyone')

          expect(stored_password?(created['_id'], 'easyone')).to eq true
          expect(stored(created['_id']).keys).not_to include('secret', 'secret_confirmation')
        end

        it 'stores a password given without its confirmation' do
          created = create_with(secret: 'easyone')

          expect(stored_password?(created['_id'], 'easyone')).to eq true
        end

        it 'stores the password as it was typed, markup included' do
          created = create_with(secret: 'a<b&c>d!')

          expect(stored_password?(created['_id'], 'a<b&c>d!')).to eq true
        end

        [nil, '', '   '].each do |blank|
          it "stores no password for #{blank.inspect}" do
            created = create_with(secret: blank)

            expect(created['errors']).to be_blank
            expect(stored(created['_id']).keys).not_to include('secret', 'secret_hash')
          end
        end

        it 'stores nothing for a confirmation given without a password' do
          created = create_with(secret: nil, secret_confirmation: 'easyone')

          expect(created['errors']).to be_blank
          expect(stored(created['_id']).keys).not_to include('secret', 'secret_confirmation', 'secret_hash')
        end

        it 'refuses a password shorter than six characters' do
          refuses({ secret: 'easy' }, 'secret', 'is too short (minimum is 6 characters)')
        end

        [false, [], {}, 123456, "\xFFeasyone".dup.force_encoding('UTF-8'), "easy\0one"].each do |bad|
          it "refuses #{bad.inspect} as a password" do
            refuses({ secret: bad }, 'secret')
          end
        end

        it 'refuses a password longer than bcrypt reads, counted in bytes' do
          refuses({ secret: 'ą' * 37 }, 'secret')

          expect(create_with(secret: 'ą' * 36)['errors']).to be_blank
        end

        [['a mismatch', 'oneeasy'], ['no text', false]].each do |label, confirmation|
          it "refuses a confirmation that is #{label}" do
            refuses({ secret: 'easyone', secret_confirmation: confirmation }, 'secret_confirmation',
                    "doesn't match secret")
          end
        end

        it 'keeps a refused password out of the log' do
          logged = []
          allow(Locomotive::Common::Logger).to receive(:error) { |message| logged << message }

          create_with(secret: 'easyone', secret_confirmation: 'mismatch1')

          expect(logged.join).not_to include('easyone')
          expect(logged.join).not_to include('mismatch1')
        end

        describe 'signing up' do

          let(:writable_types) { %w(submissions members) }
          let(:auth)           { Locomotive::Steam::AuthService.new(site, service, nil) }

          def sign_up(type, password_field, entry)
            options = instance_double('AuthOptions', type: type, password_field: password_field,
                                                     entry: entry, disable_email: true)

            auth.sign_up(options, ::Liquid::Context.new)
          end

          it 'hashes the declared password field' do
            status, entry = sign_up('submissions', 'secret', valid.merge(secret: 'easyone', secret_confirmation: 'easyone'))

            expect(status).to eq :entry_created
            expect(stored_password?(entry._id, 'easyone')).to eq true
          end

          it 'refuses a sign-up without a password, writing nothing' do
            status = entry = nil

            expect { status, entry = sign_up('submissions', 'secret', valid) }
              .not_to change { stored_count }

            expect(status).to eq :invalid_entry
            expect(entry.errors[:secret]).to eq ['is too short (minimum is 6 characters)']
          end

          it 'refuses a field the schema does not declare a password, writing nothing' do
            status = entry = nil
            input  = { email: 'ada@example.com', passcode: 'easyone', passcode_confirmation: 'easyone' }

            expect { status, entry = sign_up('members', 'passcode', input) }
              .not_to change { service.all('members', _visible: nil).size }

            expect(status).to eq :invalid_entry
            expect(entry.errors[:passcode]).to eq ['is invalid']
          end

        end

        describe 'on update' do

          let!(:created) { create_with(secret: 'easyone') }

          def update_with(input)
            service.update('submissions', created['_id'], input, true)
          end

          it 'keeps the stored password when none is given' do
            stored_hash = stored(created['_id'])['secret_hash']

            update_with(name: 'Renamed')

            expect(stored(created['_id'])['secret_hash']).to eq stored_hash
          end

          [nil, '', '   '].each do |blank|
            it "keeps the stored password when given #{blank.inspect}" do
              stored_hash = stored(created['_id'])['secret_hash']

              updated = update_with(secret: blank)

              expect(updated['errors']).to be_blank
              expect(stored(created['_id'])['secret_hash']).to eq stored_hash
            end
          end

          it 'keeps the stored password when only a confirmation is given' do
            stored_hash = stored(created['_id'])['secret_hash']

            updated = update_with(secret: '', secret_confirmation: 'newsecret')

            expect(updated['errors']).to be_blank
            expect(stored(created['_id'])['secret_hash']).to eq stored_hash
          end

          it 'replaces the stored password with a new one' do
            update_with(secret: 'newsecret')

            expect(stored_password?(created['_id'], 'newsecret')).to eq true
          end

          it 'keeps the stored password when the new one is refused' do
            updated = update_with(secret: 'easy')

            expect(updated['errors']['secret']).to be_present
            expect(stored_password?(created['_id'], 'easyone')).to eq true
          end

          if store == :mongodb
            it 'hashes only a password the write gives, never text the document held' do
              raw_entries.update_one({ _id: BSON::ObjectId.from_string(created['_id'].to_s) },
                                     { '$set' => { 'secret' => 'stale-text' } })

              update_with(name: 'Renamed')

              expect(stored_password?(created['_id'], 'easyone')).to eq true
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
