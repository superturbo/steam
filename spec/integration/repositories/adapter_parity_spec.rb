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
