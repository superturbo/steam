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
          .to match_array %w(chapters makers quoted reverse_chapters specimens submissions topics)
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

      # The stores use different IDs, even when a slug is a legal ObjectId.
      it 'finds an entry whose slug spells an object id' do
        expect(makers.by_slug('0123456789abcdef01234567').name).to eq 'Hex slug'
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

      # A missing locale must not inherit the default locale's option.
      it 'filters by a localized select through the name each locale gives it' do
        expect(specimens(:en).all(tier: 'Gold').map(&:name)).to eq %w(Embedded Scalars)
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

        def another_specimens_repository
          Locomotive::Steam::ContentEntryRepository.new(
            adapter, site, AdapterParityFixture::LOCALE, type_repository)
            .with(type_repository.by_slug('specimens'))
        end

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

        it 'starts a missing float field at 0.0' do
          entry = create_specimen

          expect(specimens.inc(entry, :price).price).to eq 1.0
          expect(specimens.find(entry._id)[:price]).to eql 1.0
        end

        it 'refuses to increment a number the entry spelled as null' do
          entry = create_specimen(price: nil)

          expect { specimens.inc(entry, :price) }
            .to raise_error(Locomotive::Steam::InvalidIncrement)
          expect(specimens.find(entry._id)[:price]).to be_nil
        end

        it 'refuses to increment a field that holds no number' do
          expect { specimens.inc(create_specimen, :name, 1) }
            .to raise_error(Locomotive::Steam::InvalidIncrement, 'specimens.name is not a number')
        end

        it 'refuses an amount the field cannot hold' do
          entry = create_specimen

          [[:score, '3'], [:score, 1.5], [:price, '1']].each do |attribute, amount|
            expect { specimens.inc(entry, attribute, amount) }
              .to raise_error(Locomotive::Steam::InvalidIncrement)
          end

          stored = specimens.find(entry._id)
          expect([stored[:score], stored[:price]]).to eq [41, nil]
        end

        # The amount alone leaves the domain, though the sum would not.
        it 'refuses an amount outside the integer domain' do
          entry = create_specimen(score: -1)

          expect { specimens.inc(entry, :score, 2**63) }
            .to raise_error(Locomotive::Steam::InvalidIncrement)
          expect(specimens.find(entry._id)[:score]).to eq(-1)
        end

        # The amount is the default one; the sum is what leaves the domain.
        it 'refuses a result outside the integer domain' do
          entry = create_specimen(score: 2**63 - 1)

          expect { specimens.inc(entry, :score) }
            .to raise_error(Locomotive::Steam::InvalidIncrement)
          expect(specimens.find(entry._id)[:score]).to eq(2**63 - 1)
        end

        # BSON holds Infinity, so no store refuses the overflow on its own.
        it 'refuses a float result the domain cannot hold' do
          entry = create_specimen(price: Float::MAX)

          expect { specimens.inc(entry, :price, Float::MAX) }
            .to raise_error(Locomotive::Steam::InvalidIncrement)
          expect(specimens.find(entry._id)[:price]).to eq Float::MAX
        end

        # Seed a value that predates repository validation.
        def store_specimen(attributes = {})
          build_specimen(attributes).tap do |entity|
            specimens.adapter.create(specimens.send(:mapper), specimens.scope, entity)
            written << entity
          end
        end

        it 'refuses a stored value of the wrong numeric type' do
          whole    = store_specimen(price: 1)
          fraction = store_specimen(name: 'Fraction', score: 1.5)

          expect { specimens.inc(whole, :price) }
            .to raise_error(Locomotive::Steam::InvalidIncrement)
          expect { specimens.inc(fraction, :score) }
            .to raise_error(Locomotive::Steam::InvalidIncrement)

          expect(specimens.find(whole._id)[:price]).to eql 1
          expect(specimens.find(fraction._id)[:score]).to eql 1.5
        end

        # Ruby absorbs the smaller value, so the sum alone would look finite.
        it 'refuses a float with no room, whatever the sum rounds to' do
          entry = create_specimen(price: 1.0)

          expect { specimens.inc(entry, :price, Float::MAX) }
            .to raise_error(Locomotive::Steam::InvalidIncrement)
          expect(specimens.find(entry._id)[:price]).to eq 1.0
        end

        it 'reaches the ends of the float domain but not past them' do
          reaches = create_specimen(price: -Float::MAX)
          past    = create_specimen(name: 'Past float', price: -1.0)

          expect(specimens.inc(reaches, :price, Float::MAX).price).to eq 0.0
          expect { specimens.inc(past, :price, -Float::MAX) }
            .to raise_error(Locomotive::Steam::InvalidIncrement)
          expect(specimens.find(past._id)[:price]).to eq(-1.0)
        end

        it 'reaches the ends of the integer domain but not past them' do
          reaches = create_specimen(score: -1)
          past    = create_specimen(name: 'Past', score: -2)

          expect(specimens.inc(reaches, :score, -(2**63 - 1)).score).to eq(-2**63)
          expect { specimens.inc(past, :score, -(2**63 - 1)) }
            .to raise_error(Locomotive::Steam::InvalidIncrement)
          expect(specimens.find(past._id)[:score]).to eq(-2)
        end

        it 'reports an entry no longer in the store' do
          entry = create_specimen

          specimens.delete(entry)

          expect { specimens.inc(entry, :score) }
            .to raise_error(Locomotive::Steam::Models::Repository::RecordNotFound)
        end

        it 'reads the value to increment from the store, not from the copy it was given' do
          entry = create_specimen(score: 1)

          moved_on = another_specimens_repository
          moved_on.update(moved_on.find(entry._id).tap { |stored| stored[:score] = 10 })

          expect(specimens.inc(entry, :score).score).to eq 11
        end

        it 'refuses a result the store cannot reach, whatever the copy holds' do
          entry = create_specimen(score: 1)

          moved_on = another_specimens_repository
          moved_on.update(moved_on.find(entry._id).tap { |stored| stored[:score] = 2**63 - 1 })

          expect { specimens.inc(entry, :score) }
            .to raise_error(Locomotive::Steam::InvalidIncrement)
          expect(another_specimens_repository.find(entry._id)[:score]).to eq(2**63 - 1)
        end

        # Updating a detached copy proves the write reaches the store instead
        # of mutating the object the previous read handed back.
        it 'makes an update visible to a later read' do
          entry    = create_specimen
          detached = entry.dup.tap { |copy| copy[:score] = 99 }

          specimens.update(detached)

          expect(specimens.find(entry._id).score).to eq 99
        end

        it 'removes an entry from later reads' do
          entry = create_specimen

          expect { specimens.delete(entry) }.to change { specimens.count }.by(-1)
          expect(specimens.find(entry._id)).to be_nil
        end

        # rank follows status, so a default must not stop at the first field
        # the attributes already carry.
        it 'fills the fields a new entry leaves out' do
          given = build_specimen(status: 'live')

          expect(build_specimen.status).to eq 'draft'
          expect(given.status).to eq 'live'
          expect(given.rank).to eq 7
        end

        it 'preserves an explicit null' do
          spelled = build_specimen(status: nil)

          expect(spelled.status).to be_nil
          expect(spelled.rank).to eq 7
        end

        it 'keeps a localized default as its content type spells it' do
          expect(build_specimen.blurb.translations).to eq('en' => 'Pending', 'fr' => 'En attente')
          expect(build_specimen(blurb: { en: 'given' }).blurb[:fr]).to be_nil
          expect(build_specimen(blurb: nil).blurb[:en]).to be_nil
        end

        # Both defaults name the second option, so picking any option is not
        # the same as picking the named one.
        it 'resolves a select default to the option id its own store issued' do
          silver = option_id(:tier, 'Silver')

          expect(build_specimen.visibility_id).to eq option_id(:visibility, 'private')
          expect(build_specimen.tier_id.translations).to eq('en' => silver, 'fr' => silver)
          expect(build_specimen(visibility_id: nil).visibility_id).to be_nil
        end

        it 'gives each entry its own copy of a default' do
          build_specimen.status << ' changed'

          expect(build_specimen.status).to eq 'draft'
        end

        it 'persists and reloads applied defaults' do
          stored = specimens.find(create_specimen(status: nil)._id)
          silver = option_id(:tier, 'Silver')

          expect(stored.status).to be_nil
          expect(stored.rank).to eq 7
          expect(stored.blurb.translations).to eq('en' => 'Pending', 'fr' => 'En attente')
          expect(stored.visibility_id).to eq option_id(:visibility, 'private')
          expect(stored.tier_id.translations).to eq('en' => silver, 'fr' => silver)
        end

        it 'creates an entry that leaves a non-localized select unset' do
          entry = specimens.build(name: 'Created without a category')

          written << entry
          specimens.create(entry)

          stored = specimens.find(entry._id)

          expect(stored.name).to eq 'Created without a category'
          expect(stored.category).to be_nil
          expect(stored.attributes).not_to have_key('category_id')
        end

        it 'keeps only the option an entry chose, not the label it reads as' do
          entry  = create_specimen(category_id: option_id(:category, 'alpha'))
          stored = specimens.find(entry._id)

          expect(stored.attributes['category_id']).to eq option_id(:category, 'alpha')
          expect(stored.category[:en]).to eq 'alpha'
        end

      end

    end

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

    # A Wagon file spells every value as text; an Engine document holds it typed.
    describe 'a value spelled as text' do

      def spelled
        types = Locomotive::Steam::ContentTypeRepository.new(adapter, site, AdapterParityFixture::LOCALE)

        Locomotive::Steam::ContentEntryRepository.new(adapter, site, AdapterParityFixture::LOCALE, types)
          .with(types.by_slug('quoted')).all.first
      end

      it 'reaches both stores as the value its field keeps' do
        attributes = spelled.attributes

        expect(attributes.values_at(:score, :price, :flag)).to eq [7, 1.5, true]
        expect(attributes[:held_on]).to eq Date.new(2014, 3, 9)
        expect(attributes[:at]).to eq Time.utc(2019, 9, 10)
        expect(attributes[:payload]).to eq('a' => [1, { 'b' => nil }])
      end

      # The store answers the query itself, before an entry is ever read.
      it 'is found by the value its field keeps' do
        types = Locomotive::Steam::ContentTypeRepository.new(adapter, site, AdapterParityFixture::LOCALE)
        found = Locomotive::Steam::ContentEntryRepository.new(adapter, site, AdapterParityFixture::LOCALE, types)
                  .with(types.by_slug('quoted')).all(score: 7, flag: true)

        expect(found.map(&:name)).to eq %w(Spelled)
      end

      it 'reaches them the same way in every locale' do
        attributes = spelled.attributes

        expect(attributes[:title].translations).to eq('en' => ' Spelled en ', 'fr' => ' Spelled fr ')
        expect(attributes[:published].translations).to eq('en' => true, 'fr' => false)
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

      it 'reads a localized JSON object identically' do
        expect(entry('scalars').notes.translations)
          .to eq('en' => { 'note' => 'first' }, 'fr' => { 'note' => 'premiere' })
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

      it 'never fills a stored field from its content type default' do
        expect(entry('all-missing').status).to be_nil
        expect(entry('explicit-nils').status).to be_nil
        expect(entry('scalars').status).to eq 'published'
        expect(entry('scalars').rank).to be_nil
        expect(entry('scalars').blurb[:en]).to be_nil
        expect(entry('explicit-nils').visibility_id).to be_nil
      end

      it 'reads a date and a date-time as the same value from either store' do
        stored = entry('scalars')

        expect(stored[:held_on]).to eql Date.new(2013, 2, 11)
        expect(stored[:at]).to eql Time.utc(2012, 6, 6, 12)
      end

      it 'leaves a field the store never wrote missing' do
        expect(entry('all-missing').attributes).not_to have_key('held_on')
        expect(entry('explicit-nils').attributes['at']).to be_nil
      end

      it 'keeps missing and null numeric values nil' do
        expect(entry('explicit-nils').score).to be_nil
        expect(entry('all-missing').score).to be_nil
        expect(entry('zero').price).to be_nil
      end

      # Translation presence and effective value are verified separately.
      it 'keeps a missing locale distinct from an explicitly null one' do
        expect(entry('arrays').title.translations.key?('fr')).to eq false
        expect(entry('embedded').title.translations.key?('fr')).to eq true
        expect(entry('embedded').title.translations['fr']).to be_nil
      end

      it 'reads the effective localized value of a present locale' do
        expect(entry('scalars').title[:en]).to eq 'Scalars en'
        expect(entry('scalars').title[:fr]).to eq 'Scalars fr'
      end

      # A localized select carries both its own name and the id an entry stores.
      it 'leaves an untranslated select and metadata locale absent' do
        expect(entry('embedded').tier.translations.keys).to eq %w(en)
        expect(entry('embedded').tier_id.translations.keys).to eq %w(en)
        expect(entry('embedded').seo_title.translations.keys).to eq %w(en)
      end

      it 'reads no effective value for a missing or explicitly null locale' do
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
