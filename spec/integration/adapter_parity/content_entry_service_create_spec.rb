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

        describe 'linking a belongs_to by its name' do

          let(:base) { { category: 'alpha' } }

          # Hidden entries count too: a refused link must not hide a write.
          def stored_count
            service.all('specimens', _visible: nil).size
          end

          def id_of(type_slug, slug)
            entries_of(type_slug).all(_slug: slug, _visible: nil).first._id
          end

          def create_with(input)
            @created = (@created || 0) + 1
            service.create('specimens', base.merge(name: "Linked #{@created}").merge(input), true)
          end

          def stored_maker_id(created)
            stored_specimen(created['_id']).attributes[:maker_id]
          end

          def raw_entries
            AdapterParityFixture.mongodb_client[AdapterParityFixture::MongoDBDocuments::CONTENT_ENTRIES_COLLECTION]
          end

          let(:writable_types) { %w(specimens submissions makers) }
          let(:inserted_ids)   { [] }

          # The shared cleanup misses a maker another site holds; drop what was inserted.
          after { raw_entries.delete_many('_id' => { '$in' => inserted_ids }) if inserted_ids.any? }

          def store_maker(id: nil, slug:, site_id: nil, visible: true)
            if filesystem?
              makers = entries_of('makers')
              makers.create(makers.build({ name: "Maker #{slug}", _slug: slug, _visible: visible }
                                           .merge(id ? { _id: id } : {})))
            else
              document = raw_entries.find(_id: id_of('makers', 'maker-two')).first
              slugs    = slug.is_a?(Hash) ? slug : { 'en' => slug }
              id ||= BSON::ObjectId.new
              raw_entries.insert_one(document.merge('_id' => id, '_slug' => slugs, '_visible' => visible)
                                             .merge(site_id ? { 'site_id' => site_id } : {}))
              inserted_ids << id
            end
          end

          def refuses(input, field)
            entry = nil

            expect { entry = create_with(input) }.not_to change { stored_count }

            expect(entry['errors'][field]).to eq ['is invalid']
          end

          describe 'a belongs_to' do

            it 'links the entry a slug names' do
              expect(stored_maker_id(create_with(maker: 'maker-one'))).to eq id_of('makers', 'maker-one')
            end

            it 'links the entry an id names' do
              maker_two = id_of('makers', 'maker-two')

              expect(stored_maker_id(create_with(maker: maker_two.to_s))).to eq maker_two
            end

            it 'links one entry that a text names both by id and by slug' do
              same = 'abcdefabcdefabcdefabcdef'
              store_maker(id: (filesystem? ? nil : BSON::ObjectId.from_string(same)), slug: same)

              expect(id_of('makers', same).to_s).to eq same
              expect(stored_maker_id(create_with(maker: same))).to eq id_of('makers', same)
            end

            context 'given an id or an entry rather than text' do

              # The Hex slug maker's slug spells the twin's id; only text may read it.
              let(:hex) { '0123456789abcdef01234567' }

              before do
                id = filesystem? ? [hex, 'typed-twin'] : BSON::ObjectId.from_string(hex)
                store_maker(id: id, slug: 'typed-twin')
              end

              def twin
                entries_of('makers').all(_slug: 'typed-twin', _visible: nil).first
              end

              it 'links the entry an entry names, by its id alone' do
                expect(stored_maker_id(create_with(maker: twin))).to eq(filesystem? ? 'typed-twin' : twin._id)
              end

              it 'refuses an entry of another type, even one whose id a maker shares' do
                # This fixture entry uses its slug as its Filesystem ID, and so does the new maker.
                store_maker(slug: 'topic-a') if filesystem?

                refuses({ maker: entries_of('topics').by_slug('topic-a') }, 'maker')
              end

              it 'refuses an entry another site holds' do
                maker = entries_of('makers').by_slug('maker-one').dup
                maker[:site_id] = 'another-site'

                refuses({ maker: maker }, 'maker')
              end

              it 'links the entry a decorated entry wraps' do
                decorated = Locomotive::Steam::Decorators::I18nDecorator.new(twin, :en)

                expect(stored_maker_id(create_with(maker: decorated))).to eq(filesystem? ? 'typed-twin' : twin._id)
              end

              it 'refuses an object that only looks like an entry' do
                impostor = Struct.new(:content_type_id).new(type_repository.by_slug('makers')._id)

                refuses({ maker: impostor }, 'maker')
              end

              it 'refuses an entry that names no site' do
                orphan = Locomotive::Steam::ContentEntry.new(_id: twin._id, name: 'Orphan')
                orphan.content_type = type_repository.by_slug('makers')

                refuses({ maker: orphan }, 'maker')
              end

              # Only MongoDB issues an id object of its own.
              if store == :mongodb
                it 'links the entry a store id names, by its id alone' do
                  expect(stored_maker_id(create_with(maker: BSON::ObjectId.from_string(hex)))).to eq twin._id
                end
              end

            end

            it 'refuses a text naming one entry by id and another by slug' do
              hex = '0123456789abcdef01234567'
              # A Wagon pull gives a Filesystem entry a [remote id, slug] identity.
              store_maker(id: (filesystem? ? [hex, 'id-twin'] : BSON::ObjectId.from_string(hex)), slug: 'id-twin')

              refuses({ maker: hex }, 'maker')
            end

            # Wagon pull can give a Filesystem entry a composite identity.
            if store == :filesystem
              it 'links a pulled entry by either part of its identity and stores its slug' do
                store_maker(id: ['5f1111111111111111111111', 'pulled-maker'], slug: 'pulled-maker')

                ['pulled-maker', '5f1111111111111111111111'].each do |reference|
                  expect(stored_maker_id(create_with(maker: reference))).to eq 'pulled-maker'
                end
                expect(stored_maker_id(create_with(maker_id: '5f1111111111111111111111'))).to eq 'pulled-maker'
              end
            end

            it 'links a hidden target' do
              store_maker(slug: 'hidden-maker', visible: false)

              expect(stored_maker_id(create_with(maker: 'hidden-maker'))).to eq id_of('makers', 'hidden-maker')
            end

            # Only MongoDB keeps several sites in one store.
            if store == :mongodb
              it 'refuses a target another site holds' do
                store_maker(slug: 'foreign-maker', site_id: BSON::ObjectId.new)

                refuses({ maker: 'foreign-maker' }, 'maker')
              end
            end

            [/maker-one/, 42, 1.5, true, "\xFFmaker".dup.force_encoding('UTF-8')].each do |value|
              it "refuses #{value.inspect} without an error" do
                refuses({ maker: value }, 'maker')
              end
            end

            it 'reads a number as no reference, even where a slug spells it' do
              store_maker(slug: '42')

              refuses({ maker: 42 }, 'maker')
              expect(stored_maker_id(create_with(maker: '42'))).to eq id_of('makers', '42')
            end

            it 'reads a symbol as the text it spells' do
              expect(stored_maker_id(create_with(maker: :'maker-one'))).to eq id_of('makers', 'maker-one')
            end

            it 'links the name a form sends as a text key' do
              form    = { 'name' => 'Form link', 'category' => 'alpha', 'maker' => 'maker-one' }
              created = service.create('specimens', form, true)

              expect(stored_maker_id(created)).to eq id_of('makers', 'maker-one')
            end

            it 'refuses the same name given as a symbol and as a text key' do
              refuses({ maker: 'maker-one', 'maker' => 'maker-two' }, 'maker')
            end

            it 'moves the link on a successful update' do
              created = create_with(maker: 'maker-one')

              updated = service.update('specimens', created['_id'], { maker: 'maker-two' }, true)

              expect(updated['errors']).to be_blank
              expect(stored_specimen(created['_id']).attributes[:maker_id]).to eq id_of('makers', 'maker-two')
            end

            it 'keeps the stored link when an update is refused' do
              created = create_with(maker: 'maker-one')

              updated = service.update('specimens', created['_id'], { maker: 'no-such-maker' }, true)

              expect(updated['errors']['maker']).to eq ['is invalid']
              expect(stored_specimen(created['_id']).attributes[:maker_id]).to eq id_of('makers', 'maker-one')
            end

            it 'links a slug that holds an ampersand and stores its id as given' do
              store_maker(slug: 'r&d-maker')

              expect(stored_maker_id(create_with(maker: 'r&d-maker'))).to eq id_of('makers', 'r&d-maker')
            end

            it 'refuses a name no entry of the target type holds' do
              refuses({ maker: 'no-such-maker' }, 'maker')
              refuses({ maker: 'topic-a' }, 'maker')
            end

            it 'hands back and logs a refused link as no value' do
              logged = []
              allow(Locomotive::Common::Logger).to receive(:error) { |message| logged << message }

              expect(create_with(maker: 'no-such-maker')['maker_id']).to be_nil
              expect(logged.join).to match(/"maker_id"\s*=>\s*nil/)
            end

            it 'refuses the name and the id of the same link in one write' do
              refuses({ maker: 'maker-one', maker_id: id_of('makers', 'maker-one') }, 'maker')
            end

            it 'refuses a list for a single link' do
              refuses({ maker: ['maker-one'] }, 'maker')
            end

            it 'reads the slug in the locale that writes' do
              store_maker(slug: { 'en' => 'en-slug-maker', 'fr' => 'fr-slug-maker' })

              refuses({ maker: 'fr-slug-maker' }, 'maker')

              created = service_in(:fr).create('specimens', base.merge(name: 'Linked fr', maker: 'fr-slug-maker'), true)
              expect(stored_maker_id(created)).to eq id_of('makers', 'en-slug-maker')
            end

            [nil, ''].each do |blank|
              it "clears the link given #{blank.inspect}" do
                created = create_with(maker: 'maker-one')

                service.update('specimens', created['_id'], { maker: blank })

                expect(stored_specimen(created['_id']).attributes[:maker_id]).to be_nil
              end
            end

          end

          describe 'an id alias' do

            it 'links the entry its id names' do
              maker_one = id_of('makers', 'maker-one')

              expect(stored_maker_id(create_with(maker_id: maker_one))).to eq maker_one
            end

            it 'refuses an id no entry holds' do
              refuses({ maker_id: 'no-such-maker' }, 'maker')
            end

            it 'reads its value as an id, never as a slug' do
              if filesystem?
                # This fixture entry uses its slug as its Filesystem ID.
                expect(stored_maker_id(create_with(maker_id: 'maker-two'))).to eq id_of('makers', 'maker-two')
              else
                refuses({ maker_id: 'maker-two' }, 'maker')
              end
            end

          end

        end

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

        it 'hands back an unknown option as no value' do
          entry = service.create('specimens', { name: 'Bogus option', topic_ids: [], category: 'bogus', tier: 'bogus' }, true)

          expect(entry.values_at('category_id', 'tier_id')).to eq [nil, nil]
        end

        it 'hands back no locale of an option one locale refused, under either name' do
          entry = service_in('fr').build('specimens', name: 'Mixed option', topic_ids: [],
                                                      tier: { 'en' => 'Gold', 'fr' => 'bogus' })

          expect(entry.valid?).to eq false
          expect([entry.__getobj__.tier, entry.__getobj__.tier_id]).to eq [nil, nil]
          expect(entry.as_json['tier_id']).to be_nil
          expect(entry.__with_locale__('en') { entry.as_json['tier_id'] }).to be_nil
          expect(entry.valid?).to eq false
          expect(entry.errors[:tier]).to eq ['is invalid']
        end

        it 'keeps the stored option when an update refuses one in another locale' do
          created = service.create('specimens', { name: 'Stored option', topic_ids: [], tier: 'Gold' }, true)

          updated = service_in('fr').update('specimens', created['_id'], { tier: 'bogus' }, true)

          expect(updated['errors']['tier']).to eq ['is invalid']
          expect(updated['tier_id']).to be_nil
          expect(stored_specimen(created['_id']).attributes[:tier_id]['en'].to_s).to eq option_id(:tier, 'Gold').to_s
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
