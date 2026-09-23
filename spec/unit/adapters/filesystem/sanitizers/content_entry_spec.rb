require 'spec_helper'
require 'tmpdir'

require_relative '../../../../../lib/locomotive/steam/adapters/filesystem.rb'

describe Locomotive::Steam::Adapters::Filesystem::Sanitizers::ContentEntry do

  let(:locales) { %w(en fr nb) }

  around do |example|
    Dir.mktmpdir do |dir|
      @site_path = dir
      example.run
    end
  end

  def write(relative_path, content)
    path = File.join(@site_path, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def load_site(bands:, notes: nil)
    write('config/site.yml', "name: Slugs\nsubdomain: slugs\nlocales: #{locales.inspect}\ntimezone: 'UTC'\n")
    write('app/content_types/bands.yml',
          "name: Bands\nslug: bands\nlabel_field_name: name\nfields:\n- name:\n    type: string\n")
    write('data/bands.yml', bands)

    if notes
      write('app/content_types/notes.yml',
            "name: Notes\nslug: notes\nlabel_field_name: title\nfields:\n- title:\n    type: string\n    localized: true\n")
      write('data/notes.yml', notes)
    end
  end

  def repository(type = 'bands', locale = :en)
    @adapter ||= Locomotive::Steam::FilesystemAdapter.new(@site_path).tap { |adapter| adapter.cache = InstanceCacheStore.new }
    site  = Locomotive::Steam::SiteRepository.new(@adapter).by_handle_or_domain('slugs', nil)
    types = Locomotive::Steam::ContentTypeRepository.new(@adapter, site, locale)

    Locomotive::Steam::ContentEntryRepository.new(@adapter, site, locale, types).with(types.by_slug(type))
  end

  def slug_of(label, type = 'bands')
    repository(type).all.detect { |entry| entry._label == label }[:_slug]
  end

  def every_locale(slug)
    locales.to_h { |locale| [locale, slug] }
  end

  describe 'a slug generated from a label with no translations' do

    before { load_site(bands: "- Pearl Jam: {}\n") }

    it 'holds the same slug in every site locale' do
      slug = slug_of('Pearl Jam')

      expect(slug.translations).to eq every_locale('pearl-jam')
      expect(slug.scalar_fallback?).to be false
    end

    it 'is present in every locale' do
      locales.each do |locale|
        expect(repository('bands', locale).all('_slug.exists' => true).map(&:name)).to eq ['Pearl Jam']
      end
    end

  end

  describe 'a slug given as one value' do

    before { load_site(bands: "- Pearl Jam:\n    _slug: chosen\n") }

    it 'holds that value in every site locale and nowhere else' do
      slug = slug_of('Pearl Jam')

      expect(slug.translations).to eq every_locale('chosen')
      expect(slug[:de]).to be_nil
    end

  end

  describe 'a slug given as a blank value' do

    it 'is generated from the label instead' do
      ["_slug:\n", "_slug: ''\n"].each do |blank|
        load_site(bands: "- Pearl Jam:\n    #{blank}")
        @adapter = nil

        expect(slug_of('Pearl Jam').translations).to eq every_locale('pearl-jam')
      end
    end

  end

  describe 'a slug given per locale' do

    it 'keeps a full set as written' do
      load_site(bands: "- Pearl Jam:\n    _slug:\n      en: pj\n      fr: pj-fr\n      nb: pj-nb\n")

      expect(slug_of('Pearl Jam').translations).to eq('en' => 'pj', 'fr' => 'pj-fr', 'nb' => 'pj-nb')
    end

    it 'keeps a partial set partial' do
      load_site(bands: "- Pearl Jam:\n    _slug:\n      en: only-en\n")

      slug = slug_of('Pearl Jam')

      expect(slug.translations).to eq('en' => 'only-en')
      expect(slug[:nb]).to be_nil
    end

  end

  describe 'a slug generated from a translated label' do

    before do
      load_site(bands: "- Pearl Jam: {}\n",
                notes: "- Hello:\n    title:\n      fr: Bonjour\n")
    end

    it 'follows each translation, falling back to the default one' do
      expect(repository('notes').all.first[:_slug].translations)
        .to eq('en' => 'hello', 'fr' => 'bonjour', 'nb' => 'hello')
    end

  end

  describe 'a generated slug another entry already holds' do

    it 'moves aside for a slug generated before it' do
      load_site(bands: "- A B: {}\n- A-B: {}\n")

      expect(slug_of('A B').translations).to eq every_locale('a-b')
      expect(slug_of('A-B').translations).to eq every_locale('a-b-1')
    end

    it 'moves aside for a slug given as one value' do
      load_site(bands: "- A B: {}\n- Given:\n    _slug: a-b\n")

      expect(slug_of('A B').translations).to eq every_locale('a-b-1')
    end

    it 'moves aside when only another locale holds it' do
      load_site(bands: "- Given:\n    _slug:\n      en: solo\n      fr: a-b\n- A B: {}\n")

      expect(slug_of('A B').translations).to eq every_locale('a-b-1')
    end

    it 'moves aside for an entry created after the site loads' do
      load_site(bands: "- A B: {}\n")

      created = repository.create(repository.build(name: 'A-B'))

      expect(created[:_slug].translations).to eq every_locale('a-b-1')
    end

  end

  describe 'the stored form of a generated slug' do

    it 'serializes as one value per site locale' do
      load_site(bands: "- Pearl Jam: {}\n")

      entry = repository.all.first

      expect(repository.send(:mapper).serialize(entry)['_slug']).to eq every_locale('pearl-jam')
    end

    context 'on a site with one locale' do

      let(:locales) { %w(en) }

      it 'serializes as that one locale' do
        load_site(bands: "- Pearl Jam: {}\n")

        entry = repository.all.first

        expect(repository.send(:mapper).serialize(entry)['_slug']).to eq('en' => 'pearl-jam')
      end

    end

  end

end
