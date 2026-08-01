require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'
require_relative '../../support/adapter_parity_fixture'

# Both adapter datasets come from one Wagon fixture. Fixed expectations prevent
# a shared bug from passing as parity.
describe 'Adapter parity' do

  CASES = [
    { desc: 'exists true matches a present field, null included',
      conditions: { 'score.exists' => true },
      expected: %w(arrays embedded explicit-nils scalars zero) },

    { desc: 'exists false matches only an absent field',
      conditions: { 'score.exists' => false }, expected: %w(all-missing) },

    { desc: 'a scalar equals an array field element',
      conditions: { labels: 'x' }, expected: %w(arrays) },

    { desc: 'an embedded document matches in key order',
      conditions: { payload: { 'b' => 2, 'a' => 1 } }, expected: %w(embedded) },

    { desc: 'an embedded document does not match reordered',
      conditions: { payload: { 'a' => 1, 'b' => 2 } }, expected: [] },

    { desc: 'equality on a boolean field',
      conditions: { flag: false }, expected: %w(arrays embedded zero) },

    { desc: 'equality on a select field resolves the option name',
      conditions: { category: 'alpha' }, expected: %w(scalars) },

    { desc: 'gt on a numeric field',
      conditions: { 'score.gt' => 5 }, expected: %w(arrays) }
  ].freeze

  # Memory casts missing and null integers to 0 before matching; MongoDB filters
  # raw BSON.
  NULL_CASES = [
    { desc: 'eq nil matches a missing or null field',
      conditions: { score: nil }, expected: %w(all-missing explicit-nils) },

    { desc: 'ne nil matches only present, non-null fields',
      conditions: { 'score.ne' => nil }, expected: %w(arrays embedded scalars zero) },

    { desc: 'in [nil] matches a missing or null field',
      conditions: { 'score.in' => [nil] }, expected: %w(all-missing explicit-nils) },

    { desc: 'nin [nil] excludes a missing or null field',
      conditions: { 'score.nin' => [nil] }, expected: %w(arrays embedded scalars zero) }
  ].freeze

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

      it 'walks the same parent-child hierarchy' do
        about = pages.by_fullpath('about')

        expect(about.title[AdapterParityFixture::LOCALE]).to eq 'About'
        expect(about.depth).to eq 1
        expect(about.position).to eq 1
        expect(pages.parent_of(about).fullpath[AdapterParityFixture::LOCALE]).to eq 'index'
        expect(pages.children_of(pages.root).map { |page| page.fullpath[AdapterParityFixture::LOCALE] }).to eq %w(about)
      end

      # Engine defaults published to false and the Steam entity to true, so a
      # dropped field reads back fine yet disappears from #published.
      it 'keeps publication and listing behaviour' do
        expect(pages.published.map { |page| page.fullpath[AdapterParityFixture::LOCALE] })
          .to match_array %w(index about)

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

    it 'holds the same rows in both stores' do
      expect(slugs({})).to match_array %w(all-missing arrays embedded explicit-nils scalars zero)
    end

    CASES.each do |c|
      it(c[:desc]) { expect(slugs(c[:conditions])).to match_array(c[:expected]) }
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

      it 'reads a scalar, a boolean and a date identically' do
        expect(entry('scalars').score).to eq 5
        expect(entry('scalars').flag).to eq true
        expect(entry('zero').score).to eq 0
        expect(entry('scalars').at.to_i).to eq Time.utc(2012, 6, 6, 12, 0, 0).to_i
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

      it 'reads a null scalar as nil, not as zero' do
        pending 'ContentEntry#_cast_integer turns a null into 0 on both stores'
        expect(entry('explicit-nils').score).to be_nil
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

    NULL_CASES.each do |c|
      it(c[:desc]) do
        pending 'Memory filters through the accessor, where nil.to_i is 0' if filesystem?
        expect(slugs(c[:conditions])).to match_array(c[:expected])
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
