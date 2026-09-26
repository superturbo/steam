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

        describe 'refusing public input' do

          let(:writable) { { name: 'Refused', category: 'alpha', topic_ids: [] } }

          # Include makers in cleanup if the rejected has_many write slips through.
          let(:writable_types) { %w(specimens submissions makers) }

          # Hidden entries count too: a refused visibility must not hide a write.
          def stored_count(type_slug = 'specimens')
            service.all(type_slug, _visible: nil).size
          end

          { 'the visibility'             => { _visible: false },
            'the position'               => { _position: 3 },
            'a belongs_to position'      => { position_in_maker: 2 },
            'a creation moment'          => { created_at: '2020-01-01T00:00:00Z' },
            'an update moment'           => { updated_at: '2020-01-01T00:00:00Z' },
            'a reset token'              => { _auth_reset_token: 'token-secret-1' },
            'a reset moment'             => { _auth_reset_sent_at: '2020-01-01T00:00:00Z' },
            'an undeclared name'         => { colour: 'red' },
            'a belongs_to by its name'   => { maker: 'maker-one' },
            'a many_to_many by its name' => { topics: ['topic-a'] }
          }.each do |label, input|
            it "refuses #{label} and writes nothing" do
              entry = nil

              expect { entry = service.create('specimens', writable.merge(input), true) }
                .not_to change { stored_count }

              expect(entry['errors'][input.keys.first.to_s]).to eq ['is invalid']
            end
          end

          it 'refuses a system name however its key is spelled' do
            [{ '_visible' => false }, { _visible: false }].each do |input|
              entry = service.create('specimens', writable.transform_keys(&:to_s).merge(input), true)

              expect(entry['errors']['_visible']).to eq ['is invalid']
            end

            expect(service.all('specimens', _visible: nil).map(&:name)).not_to include 'Refused'
          end

          it 'hands back an entry without the refused value' do
            entry = service.create('specimens', writable.merge(_visible: false), true)

            expect(entry['_visible']).to be true
          end

          it 'keeps a refused value out of the log' do
            logged = []
            allow(Locomotive::Common::Logger).to receive(:error) { |message| logged << message }

            service.create('specimens', writable.merge(_auth_reset_token: 'token-secret-1'))

            expect(logged.join).to include '_auth_reset_token'
            expect(logged.join).not_to include 'token-secret-1'
          end

          it 'keeps the refusal through another validation' do
            entry = service.create('specimens', writable.merge(_visible: false))

            expect(entry.valid?).to be false
            expect(entry.errors['_visible']).to eq ['is invalid']
          end

          it 'reports a key that is no field name as refused input' do
            entry = service.create('specimens', writable.merge('<b>odd</b>' => 'x'), true)

            expect(entry['errors'].keys).to eq ['_input']
          end

          it 'reports a key that is no valid text as refused input' do
            entry = service.create('specimens', writable.merge("\xFFodd".dup.force_encoding('UTF-8') => 'x'), true)

            expect(entry['errors'].keys).to eq ['_input']
          end

          it 'treats nil as empty attributes' do
            entry = nil

            expect { entry = service.create('specimens', nil, true) }.to change { stored_count }.by(1)

            expect(entry['errors']).to be_blank
          end

          it 'still accepts a slug and the SEO attributes' do
            created = service.create('specimens', writable.merge(_slug: 'seo-custom', seo_title: 'Seo title'))

            expect(created.errors).to be_empty
            expect(service.find('specimens', 'seo-custom')).not_to be_nil
          end

          [['name'], 'name', false].each do |input|
            it "refuses #{input.inspect} as a whole and writes nothing" do
              entry = nil

              expect { entry = service.create('specimens', input, true) }.not_to change { stored_count }

              expect(entry['errors']).to eq('_input' => ['is invalid'])
            end
          end

          it 'refuses a has_many on the entry that owns it' do
            specimen = entries_of('specimens').by_slug('scalars')
            entry    = nil

            expect { entry = service.create('makers', { name: 'Refused maker', specimens: [specimen._id] }, true) }
              .not_to change { stored_count('makers') }

            expect(entry['errors']['specimens']).to eq ['is invalid']
          end

          it 'builds an entry without the refused value' do
            entry = service.build('specimens', writable.merge(_visible: false, _auth_reset_token: 'token-secret-1'))

            expect(entry[:_visible]).to be true
            expect(entry.attributes).not_to have_key(:_auth_reset_token)
          end

          it 'reports the refusal on a built entry at once and after validation' do
            entry = service.build('specimens', writable.merge(_visible: false))

            expect(entry.errors['_visible']).to eq ['is invalid']

            entry.valid?

            expect(entry.errors['_visible']).to eq ['is invalid']
          end

          describe 'through an action' do

            let(:context) { ::Liquid::Context.new({}, {}, { session: {}, cookies: {} }) }
            let(:actions) do
              Locomotive::Steam::ActionService.new(instance_double('Site', as_json: {}), nil, content_entry: service)
            end

            it 'hands the refusal back to createEntry and writes nothing' do
              script = "return createEntry('specimens', { name: 'Acted', category: 'alpha', topic_ids: [], " \
                       "_visible: false }).errors;"

              errors = nil

              expect { errors = actions.run(script, {}, context) }.not_to change { stored_count }
              expect(errors).to eq('_visible' => ['is invalid'])
            end

            it 'refuses a list given to createEntry' do
              errors = actions.run("return createEntry('specimens', ['name']).errors;", {}, context)

              expect(errors).to eq('_input' => ['is invalid'])
            end

          end

        end

        it 'creates an entry a later read can see' do
          entry = nil

          expect { entry = service.create('submissions', valid) }
            .to change { service.all('submissions').size }.by(1)

          expect(entry['name']).to eq 'Ada'
          expect(entry['errors']).to be_blank
        end

        it 'resolves a select name to the option id its own store issued' do
          created = service.create('specimens', name: 'Named option', topic_ids: [], category: 'alpha')
          stored  = stored_specimen(created._id)

          expect(stored.attributes['category_id']).to eq option_id(:category, 'alpha')
          expect(stored.category[:en]).to eq 'alpha'
        end

        it 'resolves a localized hash of option names locale by locale' do
          created = service.create('specimens', name: 'Localized names', topic_ids: [],
                                                tier: { en: 'Gold', fr: 'Argent' })

          expect(stored_specimen(created._id).attributes['tier_id'].translations)
            .to eq('en' => option_id(:tier, 'Gold'), 'fr' => option_id(:tier, 'Silver'))
        end

        it 'resolves an option name before HTML sanitization' do
          created = service.create('specimens', name: 'Ampersand option', topic_ids: [], tier: 'R&D')

          expect(stored_specimen(created._id).attributes['tier_id'].translations)
            .to eq('en' => option_id(:tier, 'R&D'))
        end

        it 'writes a scalar name into the locale that sent it' do
          created = service_in(:fr).create('specimens', name: 'Scalar fr option', topic_ids: [],
                                                        tier: 'Or')

          expect(stored_specimen(created._id).attributes['tier_id'].translations)
            .to eq('fr' => option_id(:tier, 'Gold'))
        end

        it 'refuses an unknown option name without writing anything' do
          entry = nil

          expect { entry = service.create('specimens', { name: 'Bogus option', topic_ids: [], category: 'bogus' }, true) }
            .not_to change { service.all('specimens').size }

          expect(entry['errors']['category']).to be_present
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
