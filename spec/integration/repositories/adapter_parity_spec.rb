require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'
require_relative '../../support/adapter_parity_fixture'

# Both adapter datasets come from one Wagon fixture. Fixed expectations prevent
# a shared bug from passing as parity.
describe 'Adapter parity' do

  shared_examples_for 'the adapter parity dataset' do

    let(:site_repository) { Locomotive::Steam::SiteRepository.new(adapter) }
    let(:site)            { site_repository.by_handle_or_domain('adapter-parity', nil) }
    let(:type_repository) { Locomotive::Steam::ContentTypeRepository.new(adapter, site, AdapterParityFixture::LOCALE) }

    def slugs(conditions)
      repository = Locomotive::Steam::ContentEntryRepository.new(
        adapter, site, AdapterParityFixture::LOCALE, type_repository)

      repository.with(type_repository.by_slug('specimens')).all(conditions).map do |entry|
        entry._slug[AdapterParityFixture::LOCALE]
      end
    end

    # Each store issues its own option ids, so the fixture cannot spell one.
    def option_id(field, name)
      type_repository.select_options(type_repository.by_slug('specimens'), field)
                     .detect { |option| option.name[:en] == name }._id
    end

    describe 'the site' do

      it 'is found by the domain the fixture declares' do
        expect(site_repository.by_domain('adapter-parity.example.com').handle).to eq 'adapter-parity'
      end

      it 'exposes the same public attributes' do
        expect(site.name).to eq 'Adapter parity'
        expect(site.handle).to eq 'adapter-parity'
        expect(site.locales).to eq %i(en fr)
        expect(site.default_locale).to eq :en
        expect(site.timezone_name).to eq 'UTC'
      end

    end

    describe 'the page tree' do

      let(:pages) { Locomotive::Steam::PageRepository.new(adapter, site, AdapterParityFixture::LOCALE) }

      it 'exposes the same root' do
        expect(pages.root.fullpath[AdapterParityFixture::LOCALE]).to eq 'index'
      end

      def fullpaths(list)
        list.map { |page| page.fullpath[AdapterParityFixture::LOCALE] }
      end

      # contact sorts before about on position alone, so depth cannot be the
      # only key doing the work.
      it 'orders the whole tree by depth and then position' do
        expect(fullpaths(pages.all)).to eq %w(index contact about content_type_template about/team)
      end

      it 'narrows the tree by the conditions it is given' do
        expect(fullpaths(pages.all('slug.ne' => 'about'))).to eq %w(index contact content_type_template about/team)
        expect(fullpaths(pages.matching_fullpath(%w(about about/team nowhere)))).to match_array %w(about about/team)
      end

      it 'walks the same parent-child hierarchy' do
        team = pages.by_fullpath('about/team')

        expect(team.title[AdapterParityFixture::LOCALE]).to eq 'Team'
        expect(team.depth).to eq 2
        expect(pages.parent_of(team).fullpath[AdapterParityFixture::LOCALE]).to eq 'about'
        expect(fullpaths(pages.ancestors_of(team))).to eq %w(index about about/team)
        expect(fullpaths(pages.children_of(pages.root))).to eq %w(contact about content_type_template)
      end

      it 'finds a page by the handle it declares' do
        expect(pages.by_handle('the-team').fullpath[AdapterParityFixture::LOCALE]).to eq 'about/team'
        expect(fullpaths(pages.only_handle_and_fullpath)).to match_array %w(contact about/team content_type_template)
      end

      # Each store names the target type by its own content type id, so the
      # entry has to reach its template through either spelling.
      it 'finds the template a content entry renders through' do
        entries  = Locomotive::Steam::ContentEntryRepository.new(
          adapter, site, AdapterParityFixture::LOCALE, type_repository)
        entry    = entries.with(type_repository.by_slug('specimens')).by_slug('scalars')
        template = pages.template_for(entry)

        expect(template.fullpath[AdapterParityFixture::LOCALE]).to eq 'content_type_template'
        expect(template.content_entry._slug[AdapterParityFixture::LOCALE]).to eq 'scalars'
        expect(template).not_to be_listed
      end

      it 'reads an editable element by its block and slug' do
        element = pages.editable_element_for(pages.by_fullpath('about'), 'content/banner', 'pitch')

        expect(element.content[AdapterParityFixture::LOCALE]).to eq '<h2>About</h2>'
      end

      # Engine defaults published to false and the Steam entity to true, so a
      # dropped field reads back fine yet disappears from #published.
      it 'keeps publication and listing behaviour' do
        expect(fullpaths(pages.published)).to match_array %w(index contact about content_type_template about/team)

        expect(pages.root).not_to be_listed
        expect(pages.by_fullpath('about')).to be_listed
      end

      def page_source(locale, fullpath)
        repository = Locomotive::Steam::PageRepository.new(adapter, site, locale)

        Locomotive::Steam::PageFinderService.new(repository).find(fullpath).liquid_source.strip
      end

      # Filesystem reads the template file, MongoDB a localized raw_template.
      it 'renders the same source from either store' do
        expect(page_source(:en, 'about')).to eq 'About body en'
        expect(page_source(:fr, 'a-propos')).to eq 'About body fr'
      end

      it 'resolves a localized fullpath in its own locale' do
        french = Locomotive::Steam::PageRepository.new(adapter, site, :fr)

        expect(french.by_fullpath('a-propos').title[:fr]).to eq 'A propos'
        expect(french.by_fullpath('a-propos/team').title[:fr]).to eq 'Team'
      end

    end

    describe 'the content types' do

      let(:specimens) { type_repository.by_slug('specimens') }

      it 'holds the same types under the same slugs' do
        expect(type_repository.all.map(&:slug))
          .to match_array %w(chapters makers reverse_chapters specimens submissions topics)
      end

      it 'reads what the fixture says about a type and its fields' do
        expect(specimens.description).to eq 'Every field state covered by adapter parity'
        expect(type_repository.fields_for(specimens).by_name('name').hint).to eq 'The name the entry is labelled by'
        expect(type_repository.look_for_unique_fields(specimens).keys).to eq %w(name)
      end

      it 'reads a localized select option in each locale' do
        options = type_repository.select_options(specimens, :tier)

        expect(options.map { |option| option.name.translations })
          .to eq [{ 'en' => 'Gold', 'fr' => 'Or' }, { 'en' => 'Silver', 'fr' => 'Argent' }]
      end

      # A name declared without a locale is stored differently by each side, and
      # still has to answer the same when a locale asks for it.
      it 'reads a select option declared without a locale' do
        expect(type_repository.select_options(specimens, :category).map { |option| option.name[:en] })
          .to eq %w(alpha beta gamma)
      end

    end

    describe 'the sections' do

      let(:sections) { Locomotive::Steam::SectionRepository.new(adapter, site, AdapterParityFixture::LOCALE) }

      def section(slug)
        Locomotive::Steam::SectionFinderService.new(sections).find(slug)
      end

      def drop(slug)
        Locomotive::Steam::Liquid::Drops::Section.new(section(slug), nil)
      end

      # Wagon names a section after its file, Engine stores the name.
      it 'reads back the same identity' do
        gallery = section('gallery')

        expect(gallery.slug).to eq 'gallery'
        expect(gallery.type).to eq 'gallery'
        expect(gallery.name).to eq 'Gallery'
        expect(gallery.definition['settings'].map { |setting| setting['id'] }).to eq %w(columns rows)
      end

      # Filesystem reads the template file, MongoDB the stored template.
      it 'renders the same source from either store' do
        expect(section('gallery').liquid_source.strip).to eq '<ul class="gallery"></ul>'
      end

      it 'exposes the same CSS class' do
        expect(drop('gallery').css_class).to eq 'section-gallery'
      end

      it 'reads the content a section states for itself' do
        expect(drop('gallery').settings['columns']).to eq 4
      end

      # The filesystem sanitizer copies each setting's declared default into the
      # section's own content; nothing does that on the MongoDB side, so an
      # omitted setting renders on one store and stays empty on the other.
      it 'adds nothing to the content a section omits' do
        pending 'the filesystem sanitizer materializes section setting defaults' if filesystem?

        expect(drop('gallery').settings['rows']).to be_nil
      end

      it 'gives a section without stated content nothing to read' do
        expect(drop('footer').settings['columns']).to be_nil
      end

    end

    describe 'the snippets' do

      def snippets(locale)
        Locomotive::Steam::SnippetRepository.new(adapter, site, locale)
      end

      def snippet(slug, locale)
        Locomotive::Steam::SnippetFinderService.new(snippets(locale)).find(slug)
      end

      # A file may be named more loosely than the slug it is served under, so
      # both stores have to slugify it the same way.
      it 'holds the same snippets under the same slugs' do
        expect(snippets(:en).all.map(&:slug)).to match_array %w(a_complicated-one banner greeting)
        expect(snippet('a_complicated-one', :en).liquid_source.strip).to eq 'Complicated en'
      end

      it 'reads back the same identity' do
        expect(snippet('greeting', :en).slug).to eq 'greeting'
        expect(snippet('greeting', :en).name).to eq 'Greeting'
      end

      # Filesystem keeps a template path per locale, MongoDB a template.
      it 'renders each locale from its own source' do
        expect(snippet('greeting', :en).liquid_source.strip).to eq 'Greeting en'
        expect(snippet('greeting', :fr).liquid_source.strip).to eq 'Greeting fr'
      end

      # One store is missing a file where the other is missing a key, so each
      # reaches the default locale by its own route.
      it 'falls back to the default locale where a locale is absent' do
        expect(snippet('banner', :fr).liquid_source.strip).to eq 'Banner en'
      end

    end

    describe 'the translations' do

      def translations(locale)
        Locomotive::Steam::TranslationRepository.new(adapter, site, locale)
      end

      def translator(locale)
        Locomotive::Steam::TranslatorService.new(translations(locale), locale)
      end

      it 'holds the same keys in both stores' do
        expect(translations(:en).group_by_key.keys)
          .to match_array %w(adapter_parity_english_only hello_name powered_by)
      end

      it 'finds a translation by its key' do
        expect(translations(:en).by_key('powered_by').values)
          .to eq('en' => 'Powered by', 'fr' => 'Propulsé par')
      end

      it 'translates a key in each locale' do
        expect(translator(:en).translate('powered_by')).to eq 'Powered by'
        expect(translator(:fr).translate('powered_by')).to eq 'Propulsé par'
      end

      # The value is Liquid, so both stores have to keep it renderable.
      it 'renders a translation against the given options' do
        expect(translator(:fr).translate('hello_name', 'name' => 'Ada')).to eq 'Bonjour Ada'
      end

      # Unlike a snippet, a translation does not fall back to the default
      # locale; the key itself is the answer. It is namespaced so that no I18n
      # entry another gem registers can stand in for it.
      it 'answers with the key where a locale is absent' do
        expect(translator(:fr).translate('adapter_parity_english_only')).to eq 'adapter_parity_english_only'
      end

    end

    describe 'the theme assets' do

      let(:assets) { Locomotive::Steam::ThemeAssetRepository.new(adapter, site, AdapterParityFixture::LOCALE) }
      let(:path)   { 'stylesheets/parity.css' }
      let(:served) { filesystem? ? "/#{path}" : "/sites/#{site._id}/theme/#{path}" }

      # Filesystem knows an asset by the file it read, MongoDB by its local path.
      def asset_identity(asset)
        [File.basename(asset[:local_path] || asset[:source]), asset.folder]
      end

      it 'holds only the files a store serves' do
        expect(assets.all.map { |asset| asset_identity(asset) }).to eq [['parity.css', 'stylesheets']]
      end

      # The fixture site sets no fallback asset version, isolating the checksum.
      def theme_asset_url(checksum)
        host = Locomotive::Steam::AssetHostService.new(nil, site, nil)

        Locomotive::Steam::ThemeAssetUrlService.new(assets, host, checksum).build(path.dup)
      end

      it 'builds the URL its own store serves from' do
        expect(theme_asset_url(false)).to eq served
      end

      it 'busts the cache with the asset checksum' do
        pending 'the filesystem loader sets neither local_path nor checksum' if filesystem?

        expect(theme_asset_url(true)).to eq "#{served}?#{Digest::MD5.hexdigest("body { color: #333; }\n")}"
      end

    end

    describe 'the content entry repository' do

      def specimens(locale = AdapterParityFixture::LOCALE)
        types = Locomotive::Steam::ContentTypeRepository.new(adapter, site, locale)

        Locomotive::Steam::ContentEntryRepository.new(adapter, site, locale, types)
          .with(types.by_slug('specimens'))
      end

      it 'counts what it holds' do
        expect(specimens.count).to eq 6
      end

      it 'finds one entry by its slug' do
        expect(specimens.by_slug('scalars').name).to eq 'Scalars'
      end

      def makers
        types = Locomotive::Steam::ContentTypeRepository.new(adapter, site, AdapterParityFixture::LOCALE)

        Locomotive::Steam::ContentEntryRepository.new(adapter, site, AdapterParityFixture::LOCALE, types)
          .with(types.by_slug('makers'))
      end

      # A Filesystem id is the slug itself, so a slug spelling a legal ObjectId
      # is read as that id by MongoDB and as the slug it is by Filesystem.
      it 'finds an entry whose slug spells an object id' do
        pending 'MongoDB reads a 24-hex string as an id it never issued' unless filesystem?

        expect(makers.find('0123456789abcdef01234567').name).to eq 'Hex slug'
      end

      it 'finds an entry by the id it gave it' do
        embedded = specimens.by_slug('embedded')

        expect(specimens.find(embedded._id).name).to eq 'Embedded'
        expect(specimens.all(_id: embedded._id.to_s).map(&:name)).to eq ['Embedded']
      end

      it 'reads the ends of its own order' do
        expect(specimens.first.name).to eq 'All missing'
        expect(specimens.last.name).to eq 'Zero'
      end

      it 'answers whether anything matches a condition' do
        expect(specimens.exists?(flag: true)).to be(true)
      end

      it 'reads the first entry matching a condition' do
        expect(specimens.first(flag: true).name).to eq 'Scalars'
      end

      it 'walks to the neighbours of an entry in that order' do
        embedded = specimens.by_slug('embedded')

        expect(specimens.next(embedded).name).to eq 'Explicit nils'
        expect(specimens.previous(embedded).name).to eq 'Arrays'
      end

      # Prologue and Epilogue have no part at all, Middle and Opening share
      # one, and en and fr disagree about where Finale sits.
      describe 'navigating a key with ties and nulls' do

        def entries_of(slug, locale = AdapterParityFixture::LOCALE)
          types = Locomotive::Steam::ContentTypeRepository.new(adapter, site, locale)

          Locomotive::Steam::ContentEntryRepository.new(adapter, site, locale, types)
            .with(types.by_slug(slug))
        end

        def order_of(slug, locale = AdapterParityFixture::LOCALE)
          entries_of(slug, locale).all.map { |entry| entry._slug[locale] }
        end

        def walk(step, slug, locale)
          repository = entries_of(slug, locale)

          order_of(slug, locale).map do |current|
            neighbour = repository.public_send(step, repository.by_slug(current))

            neighbour && neighbour._slug[locale]
          end
        end

        it 'reads nulls first, then the key, then the slug' do
          expect(order_of('chapters')).to eq %w(epilogue prologue finale middle opening)
          expect(order_of('chapters', :fr)).to eq %w(epilogue prologue middle finale opening)
          expect(order_of('reverse_chapters')).to eq %w(middle opening finale epilogue prologue)
          expect(order_of('reverse_chapters', :fr)).to eq %w(opening finale middle epilogue prologue)
        end

        it 'steps through that order one entry at a time' do
          [['chapters', :en], ['chapters', :fr],
           ['reverse_chapters', :en], ['reverse_chapters', :fr]].each do |slug, locale|
            order = order_of(slug, locale)

            expect(walk(:next, slug, locale)).to eq [*order.drop(1), nil]
            expect(walk(:previous, slug, locale)).to eq [nil, *order[0..-2]]
          end
        end

        # A slug-ordered type needs no separate tie-breaker.
        it 'navigates a type ordered by the slug itself' do
          topics = entries_of('topics')

          expect(topics.next(topics.by_slug('topic-a'))._slug[:en]).to eq 'topic-b'
          expect(topics.previous(topics.by_slug('topic-b'))._slug[:en]).to eq 'topic-a'
          expect(topics.next(topics.by_slug('topic-b'))).to be_nil
        end

      end

      it 'orders by a field' do
        expect(slugs(order_by: 'name')).to eq %w(all-missing arrays embedded explicit-nils scalars zero)
      end

      it 'orders the rows with no number after the ones with zero' do
        expect(slugs(order_by: 'score.desc, name'))
          .to eq %w(arrays embedded scalars zero all-missing explicit-nils)
      end

      # Embedded and Scalars both have score 5.
      it 'breaks a tie by slug, ascending and descending alike' do
        expect(slugs(order_by: 'score'))
          .to eq %w(all-missing explicit-nils zero embedded scalars arrays)
        expect(slugs(order_by: 'score.desc'))
          .to eq %w(arrays embedded scalars zero all-missing explicit-nils)
      end

      it 'preserves an explicit slug direction' do
        expect(slugs(order_by: '_slug.desc'))
          .to eq %w(zero scalars explicit-nils embedded arrays all-missing)
      end

      # Mongo would keep the last direction, the filesystem the first.
      it 'refuses a field named twice in the sequence' do
        expect { slugs(order_by: 'score.asc, score.desc') }
          .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
      end

      it 'reverses that order however the direction is spelled' do
        descending = %w(zero scalars explicit-nils embedded arrays all-missing)

        expect(slugs(order_by: 'name.desc')).to eq descending
        expect(slugs(order_by: { name: -1 })).to eq descending
      end

      # True, then false, then the rows with no value at all.
      it 'orders by a field and a direction, breaking the tie with a second' do
        expect(slugs(order_by: 'flag.desc, name'))
          .to eq %w(scalars arrays embedded zero all-missing explicit-nils)
      end

      it 'filters by a belongs_to and by its absence' do
        expect(slugs(maker: 'maker-one')).to match_array %w(arrays scalars)
        expect(slugs(maker: nil)).to match_array %w(all-missing explicit-nils zero)
      end

      it 'filters by a localized select through the name each locale gives it' do
        expect(specimens(:en).all(tier: 'Gold').map(&:name)).to eq ['Scalars']
        expect(specimens(:fr).all(tier: 'Or').map(&:name)).to eq ['Scalars']
        expect(specimens(:en).all(tier: 'Silver').map(&:name)).to eq ['Arrays']
        expect(specimens(:fr).all(tier: 'Argent').map(&:name)).to eq ['Arrays']
      end

      # A select without the localized flag resolves its option in the default
      # locale, whichever locale asks.
      it 'filters by a non-localized select through the default locale' do
        expect(specimens(:fr).all(category: 'alpha').map(&:name)).to eq ['Scalars']
      end

      it 'groups by a select option, including unused options and entries without one' do
        groups = specimens.group_by_select_option(:category)

        expect(groups.map { |group| group[:name] }).to eq ['alpha', 'beta', 'gamma', nil]
        expect(groups.map { |group| group[:entries].size }).to eq [1, 1, 0, 4]
      end

      it 'filters and orders by a date-time' do
        expect(slugs('at.lte' => Time.utc(2020, 1, 1), order_by: 'at desc')).to eq %w(arrays scalars)
      end

      it 'requires every where clause, including repeated fields' do
        expect(specimens.all { where('score.gt' => 1).where('score.lt' => 8) }.map(&:name))
          .to match_array %w(Embedded Scalars)

        expect(specimens.all { where(name: 'Scalars').where(name: 'Zero') }).to eq []
      end

      describe 'windowing' do

        it 'takes the first rows of its own order' do
          expect(specimens.all { limit(2) }.map(&:name)).to eq ['All missing', 'Arrays']
        end

        it 'skips the rows before the window' do
          expect(specimens.all { offset(4) }.map(&:name)).to eq %w(Scalars Zero)
        end

        it 'skips before it takes' do
          expect(specimens.all { offset(1).limit(2) }.map(&:name)).to eq %w(Arrays Embedded)
        end

        it 'returns no rows for a zero limit' do
          expect(specimens.all { limit(0) }).to eq []
          expect(specimens.first { limit(0) }).to be_nil
        end

        it 'validates criteria for a zero limit' do
          expect { specimens.all('$where' => 'sleep(1)') { limit(0) } }
            .to raise_error(Locomotive::Steam::Adapters::Query::UnsupportedOperator)
        end

        it 'refuses a window it cannot describe' do
          [-> { specimens.all { limit(-1) } },
           -> { specimens.all { offset(-1) } },
           -> { specimens.all { limit('2') } }].each do |query|
            expect(&query).to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
          end
        end

      end

      it 'filters and orders by a date' do
        expect(slugs('held_on.lte' => Date.new(2020, 1, 1), order_by: 'held_on desc'))
          .to eq %w(arrays scalars)
      end

      describe 'writing' do

        def build_specimen(attributes = {})
          specimens.build({ name: 'Created', score: 41,
                            category_id: option_id(:category, 'alpha') }.merge(attributes))
        end

        # Only Filesystem sanitizes a new entry into a slug, so reads here go
        # through the id both stores do issue.
        def create_specimen(attributes = {})
          specimens.create(build_specimen(attributes)).tap { |entry| written << entry }
        end

        let(:written) { [] }

        after do
          written.each { |entry| specimens.delete(entry) if entry._id && specimens.find(entry._id) }
        end

        it 'adds an entry a later read can see' do
          entry = nil

          expect { entry = create_specimen }.to change { specimens.count }.by(1)

          expect(entry._id).not_to be_nil
          expect(specimens.find(entry._id).name).to eq 'Created'
        end

        it 'increments a numeric field' do
          entry = create_specimen

          expect(specimens.inc(entry, :score).score).to eq 42
          expect(specimens.find(entry._id).score).to eq 42
        end

        # Updating a detached copy proves the write reaches the store instead
        # of mutating the object the previous read handed back.
        it 'makes an update visible to a later read' do
          entry    = create_specimen
          detached = entry.dup.tap do |copy|
            copy.attributes = copy.attributes.dup
            copy[:score]    = 99
          end

          specimens.update(detached)

          expect(specimens.find(entry._id).score).to eq 99
        end

        it 'removes an entry from later reads' do
          entry = create_specimen

          expect { specimens.delete(entry) }.to change { specimens.count }.by(-1)
          expect(specimens.find(entry._id)).to be_nil
        end

        it 'creates an entry that leaves a non-localized select unset' do
          pending 'MongoDB cannot serialize an unset non-localized select' unless filesystem?

          entry = specimens.build(name: 'Created without a category')

          written << entry
          specimens.create(entry)

          expect(specimens.find(entry._id).name).to eq 'Created without a category'
        end

      end

    end

    describe 'the content entry service' do

      let(:service) do
        entries = Locomotive::Steam::ContentEntryRepository.new(
          adapter, site, AdapterParityFixture::LOCALE, type_repository)

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

        it 'creates an entry linked to another through a belongs_to' do
          makers = Locomotive::Steam::ContentEntryRepository.new(
            adapter, site, AdapterParityFixture::LOCALE, type_repository)
            .with(type_repository.by_slug('makers'))
          entry  = nil

          expect {
            entry = service.create('specimens',
                                   name: 'Linked',
                                   category_id: option_id(:category, 'alpha'),
                                   topic_ids: [],
                                   maker_id: makers.by_slug('maker-one')._id)
          }.to change { service.all('specimens').size }.by(1)

          expect(entry.maker.name).to eq 'Maker one'
        end

        it 'creates an entry that leaves a many_to_many unset' do
          pending 'ContentEntry#to_hash reads a many_to_many the built entry never set'

          entry = service.create('specimens',
                                 name: 'Unlinked',
                                 category_id: option_id(:category, 'alpha'))

          expect(entry['name']).to eq 'Unlinked'
        end

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

      it 'keeps missing and null numeric values nil' do
        expect(entry('explicit-nils').score).to be_nil
        expect(entry('all-missing').score).to be_nil
        expect(entry('zero').price).to be_nil
      end

      # Translation presence and effective value are verified separately.
      it 'keeps a missing locale distinct from an explicitly null one' do
        pending 'the filesystem sanitizer materializes the default locale' if filesystem?

        expect(entry('arrays').title.translations.key?('fr')).to eq false
        expect(entry('embedded').title.translations.key?('fr')).to eq true
        expect(entry('embedded').title.translations['fr']).to be_nil
      end

      it 'reads the effective localized value of a present locale' do
        expect(entry('scalars').title[:en]).to eq 'Scalars en'
        expect(entry('scalars').title[:fr]).to eq 'Scalars fr'
      end

      it 'reads no effective value for a missing or explicitly null locale' do
        pending 'the filesystem sanitizer materializes the default locale' if filesystem?

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

  end

  context 'Filesystem' do

    it_should_behave_like 'the adapter parity dataset' do
      let(:adapter) { AdapterParityFixture.filesystem_adapter }

      def filesystem?; true; end
    end

  end

end
