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

        it 'stores an email as written, never as HTML' do
          created = service.create('submissions', valid)

          updated = service.update('submissions', created._id, { email: 'g&h@example.com' }, true)

          expect(updated['errors']).to be_blank
          expect(service.find('submissions', created._id).email).to eq 'g&h@example.com'
        end

        it 'refuses an email that is no single address without touching the entry' do
          created = service.create('submissions', valid)

          updated = service.update('submissions', created._id, { email: 'ada@example.com, grace@example.org' }, true)

          expect(updated['errors']['email']).to eq ['is invalid']
          expect(service.find('submissions', created._id).email).to eq 'ada@example.com'
        end

        it 'changes another field of an entry still storing an email that is no single address, keeping that email' do
          updated = service.update('members', 'legacy-member', { passcode: 'changed' }, true)

          expect(updated['errors']).to be_blank
          expect(service.find('members', 'legacy-member').passcode).to eq 'changed'
          expect(service.find('members', 'legacy-member').email).to eq 'legacy@example.com, other@example.org'
        end

        it 'refuses system input without touching the entry' do
          created = service.create('submissions', valid)

          updated = service.update('submissions', created._id, { name: 'Grace', _visible: false }, true)

          expect(updated['errors']['_visible']).to eq ['is invalid']
          expect(updated['_visible']).to be true
          stored = service.find('submissions', created._id)
          expect(stored.name).to eq 'Ada'
          expect(stored._visible).to be true
        end

        it 'hands the refusal back to updateEntry without touching the entry' do
          created = service.create('submissions', valid)
          context = ::Liquid::Context.new({}, {}, { session: {}, cookies: {} })
          actions = Locomotive::Steam::ActionService.new(instance_double('Site', as_json: {}), nil, content_entry: service)

          errors = actions.run("return updateEntry('submissions', '#{created._id}', " \
                               "{ name: 'Grace', _position: 9 }).errors;", {}, context)

          expect(errors).to eq('_position' => ['is invalid'])
          expect(service.find('submissions', created._id).name).to eq 'Ada'
        end

        describe 'the entry a write names' do

          let(:not_found) { [Locomotive::Steam::Models::Repository::RecordNotFound, 'could not find the content entry'] }

          def submission_storing(values, attributes = {})
            created    = service.create('submissions', valid.merge(attributes))
            repository = entries_of('submissions')

            repository.find(created._id).tap do |entry|
              values.each { |name, value| entry[name] = value }
              repository.update(entry)
            end
          end

          def stored_submission(id)
            entries_of('submissions').all(_id: id, _visible: nil).first
          end

          def run_action(script)
            context = ::Liquid::Context.new({}, {}, { session: {}, cookies: {} })

            Locomotive::Steam::ActionService.new(instance_double('Site', as_json: {}), nil, content_entry: service)
              .run(script, {}, context)
          end

          it 'updates a hidden entry, which stays hidden' do
            hidden = submission_storing(_visible: false)

            updated = service.update('submissions', hidden._id, { name: 'Grace' }, true)

            expect(updated['errors']).to be_blank
            expect(stored_submission(hidden._id).attributes.values_at(:name, :_visible)).to eq ['Grace', false]
          end

          it 'finds a hidden entry by its slug' do
            hidden = submission_storing({ _visible: false }, _slug: 'quiet-one')

            service.update('submissions', 'quiet-one', { name: 'Grace' })

            expect(stored_submission(hidden._id).name).to eq 'Grace'
          end

          it 'deletes a hidden entry' do
            hidden = submission_storing(_visible: false)

            service.delete('submissions', hidden._id)

            expect(stored_submission(hidden._id)).to be_nil
          end

          it 'updates through updateEntry a hidden entry the template lists' do
            hidden = submission_storing(_visible: false)

            name = run_action("var listed = allEntries('submissions', { _visible: false }); " \
                              "return updateEntry('submissions', listed[0]._id, { name: 'Grace' }).name;")

            expect(name).to eq 'Grace'
            expect(stored_submission(hidden._id).attributes.values_at(:name, :_visible)).to eq ['Grace', false]
          end

          ['no-such-entry', '0123456789abcdef01234567'].each do |unknown|

            it "reports #{unknown.inspect} as not found to an update and a delete" do
              expect { service.update('submissions', unknown, { name: 'Grace' }) }.to raise_error(*not_found)
              expect { service.delete('submissions', unknown) }.to raise_error(*not_found)
            end

          end

          [nil, ''].each do |blank|

            it "reports #{blank.inspect} as not found, leaving an entry without a slug as it was" do
              slugless = submission_storing(_slug: nil)

              expect { service.update('submissions', blank, { name: 'Grace' }) }.to raise_error(*not_found)
              expect { service.delete('submissions', blank) }.to raise_error(*not_found)
              expect(stored_submission(slugless._id).name).to eq 'Ada'
            end

          end

          it 'hands an unknown entry to updateEntry as an action error' do
            expect { run_action("updateEntry('submissions', 'no-such-entry', { name: 'Grace' });") }
              .to raise_error(Locomotive::Steam::ActionError, /could not find the content entry/)
          end

        end

        it 'treats nil as empty attributes' do
          created = service.create('submissions', valid)

          updated = service.update('submissions', created._id, nil, true)

          expect(updated['errors']).to be_blank
          expect(service.find('submissions', created._id).name).to eq 'Ada'
        end

        ['Grace', false].each do |input|
          it "refuses #{input.inspect} as a whole without touching the entry" do
            created = service.create('submissions', valid)

            updated = service.update('submissions', created._id, input, true)

            expect(updated['errors']).to eq('_input' => ['is invalid'])
            expect(service.find('submissions', created._id).name).to eq 'Ada'
          end
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

        it 'resolves a select name on update, and a null clears it' do
          created = readable_specimen(category_id: option_id(:category, 'alpha'))

          service.update('specimens', created._id, category: 'beta')
          expect(stored_specimen(created._id).attributes['category_id']).to eq option_id(:category, 'beta')

          service.update('specimens', created._id, category: nil)
          expect(stored_specimen(created._id).attributes['category_id']).to be_nil
        end

        it 'refuses an unknown option name without touching the entry' do
          created = readable_specimen(category_id: option_id(:category, 'alpha'))
          updated = service.update('specimens', created._id, { category: 'bogus' }, true)

          expect(updated['errors']['category']).to be_present
          expect(stored_specimen(created._id).attributes['category_id']).to eq option_id(:category, 'alpha')
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

        it 'relinks the associations of a decorated update' do
          created   = readable_specimen(maker_id: makers.by_slug('maker-one')._id)
          decorated = service.find('specimens', created._id)

          service.update_decorated_entry(decorated, 'maker_id' => makers.by_slug('maker-two')._id)

          expect(decorated.maker.name).to eq 'Maker two'
        end

        it 'relinks a decorated update whose association was read' do
          created   = readable_specimen(maker_id: makers.by_slug('maker-one')._id)
          decorated = service.find('specimens', created._id)
          decorated.maker.name

          service.update_decorated_entry(decorated, 'maker_id' => makers.by_slug('maker-two')._id)

          expect([stored_specimen(created._id)[:maker_id], decorated.maker.name]).to eq [makers.by_slug('maker-two')._id, 'Maker two']
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

        describe 'an entry whose type has a has_many field' do

          let(:writable_types) { %w(specimens submissions makers) }

          it 'creates and updates it, keeping the entries its has_many reads' do
            created = service.create('makers', { name: 'Fresh maker' }, true)
            readable_specimen(maker_id: created['_id'])
            updated = service.update('makers', created['_id'], { name: 'Renamed maker' }, true)
            stored  = entries_of('makers').find(created['_id'])

            expect([updated['errors'].blank?, stored.name, stored.specimens.all.map(&:name)])
              .to eq [true, 'Renamed maker', ['Readable']]
          end

          it 'writes a decorated update of it' do
            created   = service.create('makers', name: 'Fresh maker')
            decorated = service.find('makers', created._id)

            service.update_decorated_entry(decorated, 'name' => 'Renamed maker')

            expect(entries_of('makers').find(created._id).name).to eq 'Renamed maker'
          end

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
