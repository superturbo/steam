require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'

describe Locomotive::Steam::ContentEntryRepository do

  let(:_fields) { instance_double('Fields', selects: [], belongs_to: [], many_to_many: [], dates_and_date_times: [], numbers: [], booleans: []) }
  let(:type)    { build_content_type('Articles', label_field_name: :title, localized_names: [:title], fields: _fields, fields_by_name: { title: instance_double('Field', name: :title, type: :string) }, fields_with_default: []) }
  let(:entries) { [{ content_type_id: 1, _position: 0, _label: 'Update #1', title: { fr: 'Mise a jour #1' }, text: { en: 'added some free stuff', fr: 'phrase FR' }, date: '2009/05/12', category: 'General' }] }
  let(:locale)  { :en }
  let(:site)    { instance_double('Site', _id: 1, default_locale: :en, locales: %i(en fr), timezone: ActiveSupport::TimeZone['UTC']) }
  let(:adapter) { Locomotive::Steam::FilesystemAdapter.new(nil) }

  let(:content_type_repository) { instance_double('ContentTypeRepository') }
  let(:repository)  { described_class.new(adapter, site, locale, content_type_repository) }

  before do
    allow(adapter).to receive(:collection).and_return(entries)
    adapter.cache = NoCacheStore.new
  end

  describe 'lazy read wiring' do

    before { repository.with(type) }

    it '#first fetches a single entry (query#first), not #all' do
      dataset = double('dataset', first: :entry)
      allow(dataset).to receive(:all)
      allow(repository).to receive(:query).and_return(dataset)

      expect(repository.first).to eq :entry
      expect(dataset).to have_received(:first)
      expect(dataset).not_to have_received(:all)
    end

    it '#exists? checks #empty?, not #all.size' do
      dataset = double('dataset', empty?: false)
      allow(repository).to receive(:query).and_return(dataset)
      allow(dataset).to receive(:all)

      expect(repository.exists?).to be true
      expect(dataset).to have_received(:empty?)
      expect(dataset).not_to have_received(:all)
    end

  end

  describe '#dup' do

    it 'builds entities against the copy content type' do
      repository.with(type)
      repository.build({})

      copy          = repository.dup
      reloaded_type = build_content_type('Articles', _id: 1, fields_with_default: [])
      copy.with(reloaded_type)

      expect(copy.build({}).content_type).to be(reloaded_type)
    end

  end

  describe '#all' do

    let(:conditions) { nil }

    subject { repository.with(type).all(conditions) }

    it { expect(subject.size).to eq 1 }

    describe 'first element' do

      subject { repository.with(type).all(conditions).first }

      it { expect(subject.class).to eq Locomotive::Steam::ContentEntry }
      it { expect(subject._label.translations).to eq('en' => 'Update #1', 'fr' => 'Mise a jour #1') }
      it { expect(subject._slug.translations).to eq('en' => 'update-number-1', 'fr' => 'mise-a-jour-number-1') }
      it { expect(subject.title.translations).to eq('en' => 'Update #1', 'fr' => 'Mise a jour #1') }
      it { expect(subject.content_type).to eq type }

    end

    # The slug is generated metadata and covers every locale, while the label
    # the author never translated stays untranslated.
    describe 'an entry whose localized label has one locale' do

      let(:entries) { [{ content_type_id: 1, _position: 0, _label: 'English only' }] }

      subject { repository.with(type).all.first }

      it { expect(subject.title.translations).to eq('en' => 'English only') }
      it { expect(subject._slug.translations).to eq('en' => 'english-only', 'fr' => 'english-only') }

    end

    describe 'including also the not visible entries' do

      let(:entries) { [
        { content_type_id: 1, _position: 0, _label: 'Update #1', title: { fr: 'Mise a jour #1' }, text: { en: 'added some free stuff', fr: 'phrase FR' }, date: '2009/05/12', category: 'General' },
        { content_type_id: 1, _position: 1, _label: 'Update #2 [HIDDEN]', title: { fr: 'Mise a jour #1' }, text: { en: 'added some free stuff', fr: 'phrase FR' }, date: '2009/05/12', category: 'General', _visible: false }
      ] }

      let(:conditions) { { _visible: nil } }

      it { expect(subject.size).to eq 2 }

    end

  end

  describe 'reading a stored entry' do

    let(:type) do
      build_content_type('Articles', label_field_name: :title, fields: _fields, fields_with_default: [],
                         fields_by_name: { title:      instance_double('Field', name: :title, type: :string),
                                           held_on:    instance_double('Field', name: :held_on, type: :date,
                                                                       persisted_name: 'held_on'),
                                           launched_at: instance_double('Field', name: :launched_at, type: :date_time,
                                                                        persisted_name: 'launched_at') })
    end

    let(:stored)  { Date.new(2013, 2, 11) }
    let(:entries) do
      [{ content_type_id: 1, _position: 0, _label: 'Stored', held_on: stored, launched_at: '2012-06-06T12:00:00Z' }]
    end

    subject { repository.with(type).all.first }

    context 'a date the store wrote as a time' do
      let(:stored) { Time.utc(2013, 2, 11) }
      it { expect(subject[:held_on]).to eql Date.new(2013, 2, 11) }
    end

    context 'a date the store wrote as text' do
      let(:stored) { '2013-02-11' }
      it { expect(subject[:held_on]).to eql Date.new(2013, 2, 11) }
    end

    context 'an already normalized date' do
      let(:stored) { Date.new(2013, 2, 11) }
      it('is left alone') { expect(subject[:held_on]).to eql Date.new(2013, 2, 11) }
    end

    context 'a value the grammar cannot read' do
      let(:stored) { 'not a date' }

      it 'stays exactly as the store holds it' do
        expect(subject[:held_on]).to eq 'not a date'
      end
    end

    context 'a field the store never wrote' do
      let(:entries) { [{ content_type_id: 1, _position: 0, _label: 'Stored' }] }

      it { expect(subject.attributes).not_to have_key('held_on') }
    end

    it 'reads a time as UTC' do
      expect(subject[:launched_at]).to eql Time.utc(2012, 6, 6, 12)
    end

    it 'does not read a built entry the same way' do
      built = repository.with(type).build(held_on: Time.utc(2013, 2, 11))

      expect(built[:held_on]).to be_a(Time)
    end

    it 'keeps the site out of what the store is given' do
      expect(repository.with(type).send(:mapper).serialize(subject)).not_to have_key(:site)
    end

    # A calendar date names a day; the site decides which instant that is.
    context 'a date in a date time field, with the site behind UTC' do
      let(:site) do
        instance_double('Site', _id: 1, default_locale: :en, locales: %i(en fr),
                        timezone: ActiveSupport::TimeZone['America/New_York'])
      end

      let(:entries) do
        [{ content_type_id: 1, _position: 0, _label: 'Stored', launched_at: Date.new(2013, 2, 11) }]
      end

      it { expect(subject[:launched_at]).to eql Time.utc(2013, 2, 11, 5) }
    end

    context 'a localized date' do
      let(:type) do
        build_content_type('Articles', label_field_name: :title, fields: _fields, fields_with_default: [],
                           localized_names: [:held_on],
                           fields_by_name: { title:   instance_double('Field', name: :title, type: :string),
                                             held_on: instance_double('Field', name: :held_on, type: :date,
                                                                      persisted_name: 'held_on') })
      end

      let(:entries) do
        [{ content_type_id: 1, _position: 0, _label: 'Stored', held_on: { en: '2013-02-11', fr: nil } }]
      end

      it 'reads the locales the store wrote and invents none' do
        expect(subject[:held_on].translations).to eq('en' => Date.new(2013, 2, 11), 'fr' => nil)
      end

      context 'one value standing for every locale' do
        let(:entries) do
          [{ content_type_id: 1, _position: 0, _label: 'Stored', held_on: '2013-02-11' }]
        end

        it 'reads it once and leaves the locales unmaterialized' do
          expect(subject[:held_on][:fr]).to eql Date.new(2013, 2, 11)
          expect(subject[:held_on].translations).to be_empty
        end
      end
    end

    context 'without a site' do
      let(:site) { nil }

      it 'says what it is missing' do
        expect { subject }
          .to raise_error(Locomotive::Steam::ContentFieldValues::ConfigurationError, /site timezone is required/)
      end
    end

    context 'with a timezone no zone table knows' do
      let(:site) do
        instance_double('Site', _id: 1, default_locale: :en, locales: %i(en fr),
                        timezone: nil, timezone_name: 'Mars/Olympus')
      end

      let(:entries) do
        [{ content_type_id: 1, _position: 0, _label: 'Stored', launched_at: '2013-02-11T10:00:00' }]
      end

      it { expect { subject }.to raise_error(Locomotive::Steam::ContentFieldValues::ConfigurationError, /Mars/) }

      # A calendar date is read without one, so nothing asks for the zone.
      context 'over an entry holding only a date' do
        let(:type) do
          build_content_type('Articles', label_field_name: :title, fields: _fields, fields_with_default: [],
                             fields_by_name: { title:   instance_double('Field', name: :title, type: :string),
                                               held_on: instance_double('Field', name: :held_on, type: :date,
                                                                        persisted_name: 'held_on') })
        end

        let(:entries) do
          [{ content_type_id: 1, _position: 0, _label: 'Stored', held_on: '2013-02-11' }]
        end

        it { expect(subject[:held_on]).to eql Date.new(2013, 2, 11) }
      end
    end

  end

  describe '#build' do

    let(:attributes) { { title: 'Hello world' } }
    subject { repository.with(type).build(attributes) }

    it { expect(subject.title[:en]).to eq 'Hello world' }
    it { expect(subject.content_type).to eq type }

    context 'a select default naming no option' do

      let(:field) do
        instance_double('Field', name: 'visibility', persisted_name: 'visibility_id',
                        type: :select, localized?: false, default: 'nope')
      end
      let(:type) do
        build_content_type('Articles', label_field_name: :title, fields: _fields,
                           fields_with_default: [field])
      end

      it 'says which option it looked for' do
        allow(content_type_repository).to receive(:select_options).and_return([])

        expect { subject }.to raise_error(described_class::InvalidDefault,
                                          'articles.visibility has no option named "nope"')
      end

    end

  end

  describe '#exists?' do

    let(:conditions) { {} }
    subject { repository.with(type).exists?(conditions) }

    it { expect(subject).to eq true }

    context 'more specific conditions' do

      let(:conditions) { { '_slug' => 'update-number-1' } }
      it { expect(subject).to eq true }

    end

    context 'conditions which do match any entries' do

      let(:conditions) { { '_slug' => 'foo' } }
      it { expect(subject).to eq false }

    end

  end

  describe '#by_slug' do

    let(:slug) { nil }
    subject { repository.with(type).by_slug(slug) }

    it { is_expected.to eq nil }

    context 'existing slug' do
      let(:slug) { 'update-number-1' }
      it { expect(subject.title.translations).to eq('en' => 'Update #1', 'fr' => 'Mise a jour #1') }
    end

  end

  describe '#value_for' do

    let(:entry)       { nil }
    let(:conditions)  { {} }
    let(:name)        { :title }
    subject { repository.with(type).value_for(entry, name, conditions) }

    it { is_expected.to eq nil }

    context 'existing entry' do
      let(:entry) { instance_double('Entry', title: 'Hello world') }
      it { is_expected.to eq 'Hello world' }

      context 'unknown field' do
        let(:name) { :authors }
        it { is_expected.to eq nil }
      end
    end

    context 'with a has_many field' do
      let(:type) { build_content_type('Articles', label_field_name: :title, localized_names: [:title], fields: _fields, fields_by_name: { articles: instance_double('Field', type: :has_many) }, fields_with_default: []) }
      let(:proxy_repository) { repository.dup }
      let(:entry) { instance_double('Entry', articles: proxy_repository) }
      let(:name) { :articles }
      let(:conditions) { { published: true } }

      it 'does not modify the local conditions of the initial proxy repository' do
        expect(subject.local_conditions).to eq(content_type_id: 1, published: true)
        expect(proxy_repository.local_conditions).to eq(content_type_id: 1)
      end

    end

  end

  describe '#next and #previous' do

    it 'have nothing to look for without an entry' do
      expect(repository.next(nil)).to be_nil
      expect(repository.previous(nil)).to be_nil
    end

    describe 'over a type ordered by the slug itself' do

      let(:type) do
        build_content_type('Articles', order_by: { _slug: 'asc' }, label_field_name: :title,
                           fields: _fields, fields_with_default: [],
                           fields_by_name: { title: instance_double('Field', name: :title, type: :string) })
      end

      let(:entries) do
        [{ content_type_id: 1, _position: 0, _label: 'Alpha' },
         { content_type_id: 1, _position: 1, _label: 'Bravo' }]
      end

      before { repository.with(type) }

      it 'queries once because a slug identifies one entry' do
        alpha = repository.by_slug('alpha')
        allow(repository).to receive(:first).and_call_original

        expect(repository.next(alpha)._slug[:en]).to eq 'bravo'
        expect(repository).to have_received(:first).once
      end

    end

    describe 'over the order a manually sorted type has' do

      let(:type) do
        build_content_type('Articles', order_by: { _position: 'asc' }, label_field_name: :title,
                           fields: _fields, fields_with_default: [],
                           fields_by_name: { title: instance_double('Field', name: :title, type: :string) })
      end

      # Slug order would read alpha, mike, zulu.
      let(:entries) do
        [{ content_type_id: 1, _position: 0, _label: 'Zulu' },
         { content_type_id: 1, _position: 1, _label: 'Alpha' },
         { content_type_id: 1, _position: 2, _label: 'Mike' }]
      end

      before { repository.with(type) }

      it 'walks the positions and stops at their ends' do
        expect(repository.next(repository.by_slug('alpha'))._slug[:en]).to eq 'mike'
        expect(repository.previous(repository.by_slug('alpha'))._slug[:en]).to eq 'zulu'
        expect(repository.previous(repository.by_slug('zulu'))).to be_nil
        expect(repository.next(repository.by_slug('mike'))).to be_nil
      end

    end

  end

  describe '#group_by_select_option' do

    let(:type) { nil }
    let(:name) { nil }

    subject { repository.with(type).group_by_select_option(name) }

    it { is_expected.to eq({}) }

    context 'select field' do

      let(:fields) do
        {
          title:    instance_double('TitleField', name: :title, type: :string),
          category: instance_double('SelectField', name: :category, type: :select, localized: true, select_options: [])
        }
      end
      let(:type) { build_content_type('Articles', order_by: '_position asc', label_field_name: :title, localized_names: [:title, :category_id], fields: _fields, fields_by_name: fields, fields_with_default: []) }
      let(:name) { :category }

      let(:options) {
        [
          instance_double('SelectOption1', _id: '0', name: instance_double('I18nField', :[] => 'cooking', translations: { 'en' => 'cooking' })),
          instance_double('SelectOption2', _id: '1', name: instance_double('I18nField', :[] => 'wine', translations: { 'en' => 'wine' })),
          instance_double('SelectOption3', _id: '2', name: instance_double('I18nField', :[] => 'bread', translations: { 'en' => 'bread' }))
        ]
      }

      let(:entries) do
        [
          { content_type_id: 1, _position: 0, _label: 'Recipe #1', category_id: { 'en' => '0' } },
          { content_type_id: 1, _position: 1, _label: 'Recipe #2', category_id: { 'en' => '2' } },
          { content_type_id: 1, _position: 2, _label: 'Recipe #3', category_id: { 'en' => '2' } },
          { content_type_id: 1, _position: 3, _label: 'Recipe #4', category_id: { 'en' => '42' } } # unknown category
        ]
      end

      before {
        allow(content_type_repository).to receive(:select_options).and_return(options)
        %w(cooking wine bread).each_with_index do |name, position|
          allow(fields[:category].select_options).to receive(:by_id_or_name).with(position.to_s).and_return(options.at(position))
        end
        allow(fields[:category].select_options).to receive(:by_id_or_name).with('42').and_return(nil)
      }

      it { expect(subject.size).to eq 4 }
      it { expect(subject.map { |h| h[:name] }).to eq ['cooking', 'wine', 'bread', nil] }
      it { expect(subject.map { |h| h[:entries].size }).to eq [1, 0, 2, 1] }

    end

  end

  describe 'belongs_to' do

    let(:field)   { instance_double('Field', name: :author, type: :belongs_to, association_options: { target_id: 2 }) }
    let(:type)    { build_content_type('Articles', label_field_name: :title, association_fields: [field], fields_with_default: []) }
    let(:entries) { [{ content_type_id: 1, title: 'Hello world', author_id: 'john-doe' }] }
    let(:other_type)    { build_content_type('Authors', _id: 2, label_field_name: :name, fields: _fields, fields_by_name: { name: instance_double('Field', name: :name, type: :string) }, fields_with_default: []) }
    let(:other_entries) { [{ content_type_id: 2, _id: 'john-doe', name: 'John Doe' }] }

    let(:type_repository) { instance_double('ArticleBelongsToRepository', selects: [], belongs_to: [], many_to_many: [], dates_and_date_times: [], numbers: [], booleans: []) }

    before do
      allow(type).to receive(:fields).and_return(type_repository)
      allow(content_type_repository).to receive(:find).with(2).and_return(other_type)
    end

    subject { repository.with(type).by_slug('hello-world') }

    it { expect(subject.author.class).to eq Locomotive::Steam::Models::BelongsToAssociation }

    it 'calls the new repository to fetch the target entity' do
      author = subject.author
      allow(adapter).to receive(:collection).and_return(other_entries)
      expect(author.name).to eq 'John Doe'
    end

  end

  describe 'has_many' do

    let(:field)   { instance_double('Field', name: :articles, type: :has_many, association_options: { target_id: 2, inverse_of: :author, order_by: 'position_in_author' }) }
    let(:type)    { build_content_type('Authors', label_field_name: :name, association_fields: [field], fields_by_name: { articles: field }, fields_with_default: []) }
    let(:entries) { [{ content_type_id: 1, _id: 'john-doe', name: 'John Doe' }] }
    # The target declares the belongs_to named by its inverse position.
    let(:title_field)   { instance_double('Field', name: :title, type: :string) }
    let(:author_field)  { instance_double('Field', name: :author, type: :belongs_to) }
    let(:target_fields) { instance_double('Fields', selects: [], belongs_to: [author_field], many_to_many: [], dates_and_date_times: [], numbers: [], booleans: []) }
    let(:other_type) do
      build_content_type('Articles', _id: 2, label_field_name: :title, fields: target_fields,
                         fields_by_name: { title: title_field, author: author_field },
                         fields_with_default: [])
    end
    let(:other_entries) {
        [
          { content_type_id: 2, _id: 'hello-world', title: 'Hello world', author_id: 'john-doe', position_in_author: 2 },
          { content_type_id: 2, _id: 'lorem-ipsum', title: 'Lorem ipsum', author_id: 'john-doe', position_in_author: 1 },
          { content_type_id: 2, _id: 'lost', title: 'Lost', author_id: 'jane-doe' },
        ]
      }

    let(:type_repository) { instance_double('AuthorRepository', selects: [], belongs_to: [], many_to_many: [], dates_and_date_times: [], numbers: [], booleans: []) }

    before do
      allow(type).to receive(:fields).and_return(type_repository)
      allow(content_type_repository).to receive(:find).with(2).and_return(other_type)
    end

    subject { repository.with(type).by_slug('john-doe') }

    it { expect(subject.articles.class).to eq Locomotive::Steam::Models::HasManyAssociation }

    it 'calls the new repository to fetch the target entities' do
      articles = subject.articles
      allow(adapter).to receive(:collection).and_return(other_entries)
      expect(articles.all.map(&:title)).to eq ['Lorem ipsum', 'Hello world']
    end

    it 'applies a runtime order_by to the returned entries (over the field default)' do
      articles = repository.value_for(subject, :articles, order_by: 'title.asc')
      allow(adapter).to receive(:collection).and_return(other_entries)

      expect(articles.all.map(&:title)).to eq ['Hello world', 'Lorem ipsum']
    end

    it 'applies a runtime order_by given as a hash (symbol direction)' do
      articles = repository.value_for(subject, :articles, order_by: { title: :asc })
      allow(adapter).to receive(:collection).and_return(other_entries)

      expect(articles.all.map(&:title)).to eq ['Hello world', 'Lorem ipsum']
    end

    it 'does not leak a scoped copy back into the original association' do
      scoped = repository.value_for(subject, :articles, order_by: 'title.asc')
      allow(adapter).to receive(:collection).and_return(other_entries)
      scoped.all

      expect(subject.articles.all.map(&:title)).to eq ['Lorem ipsum', 'Hello world']
    end

    it 'does not change the parent scope content type when the association loads' do
      articles = subject.articles
      allow(adapter).to receive(:collection).and_return(other_entries)
      articles.all

      expect(repository.scope.context[:content_type]).to eq type
    end

    context 'the owner has a composite [mongo_id, slug] id (synced entries)' do

      let(:entries) { [{ content_type_id: 1, _id: ['5baf7d38a953300567956448', 'john-doe'], name: 'John Doe' }] }
      let(:other_entries) {
          [
            { content_type_id: 2, _id: 'hello-world', title: 'Hello world', author_id: 'john-doe',                   position_in_author: 2 },
            { content_type_id: 2, _id: 'lorem-ipsum', title: 'Lorem ipsum', author_id: '5baf7d38a953300567956448', position_in_author: 1 },
            { content_type_id: 2, _id: 'lost',        title: 'Lost',        author_id: 'jane-doe' },
            { content_type_id: 2, _id: 'orphan',      title: 'Orphan' },
          ]
        }

      it 'matches children referencing either component and skips foreign and orphan ones' do
        articles = subject.articles
        allow(adapter).to receive(:collection).and_return(other_entries)
        expect(articles.all.map(&:title)).to eq ['Lorem ipsum', 'Hello world']
      end

    end

  end

  describe 'many_to_many' do

    let(:field)   { instance_double('Field', name: :articles, type: :many_to_many, association_options: { target_id: 2, inverse_of: :authors }) }
    let(:type)    { build_content_type('Authors', label_field_name: :name, association_fields: [field], fields_by_name: { articles: field }, fields: _fields, fields_with_default: []) }
    let(:entries) { [{ content_type_id: 1, _id: 1, name: 'John Doe', article_ids: ['hello-world', 'lorem-ipsum'] }] }
    let(:other_type)    { build_content_type('Articles', _id: 2, label_field_name: :title, fields: _fields, fields_by_name: { title: instance_double('Field', name: :title, type: :string) }, fields_with_default: []) }
    let(:other_entries) {
        [
          { content_type_id: 2, _id: 'hello-world', title: 'Hello world', author_id: 'john-doe', position_in_author: 2 },
          { content_type_id: 2, _id: 'lorem-ipsum', title: 'Lorem ipsum', author_id: 'john-doe', position_in_author: 1 },
          { content_type_id: 2, _id: 'lost', title: 'Lost', author_id: 'jane-doe' },
        ]
      }

    let(:type_repository) { instance_double('AuthorRepository', selects: [], belongs_to: [], many_to_many: [], dates_and_date_times: [], numbers: [], booleans: []) }

    before do
      allow(type).to receive(:fields).and_return(type_repository)
      allow(content_type_repository).to receive(:find).with(2).and_return(other_type)
    end

    subject { repository.with(type).by_slug('john-doe') }

    it { expect(subject.articles.class).to eq Locomotive::Steam::Models::ManyToManyAssociation }

    it 'calls the new repository to fetch the target entities' do
      articles = subject.articles
      allow(adapter).to receive(:collection).and_return(other_entries)
      expect(articles.all.map(&:title)).to eq ['Hello world', 'Lorem ipsum']
    end

    it 'applies a runtime order_by to the returned entries' do
      articles = repository.value_for(subject, :articles, order_by: 'title.desc')
      allow(adapter).to receive(:collection).and_return(other_entries)

      expect(articles.all.map(&:title)).to eq ['Lorem ipsum', 'Hello world']
    end

    it 'does not leak a scoped copy back into the original association' do
      scoped = repository.value_for(subject, :articles, order_by: 'title.desc')
      allow(adapter).to receive(:collection).and_return(other_entries)
      scoped.all

      expect(subject.articles.all.map(&:title)).to eq ['Hello world', 'Lorem ipsum']
    end

  end

  describe '#all without a runtime order' do

    let(:type) do
      build_content_type('Chapters', order_by: { part: 'asc' }, label_field_name: :title,
                         fields: _fields, fields_with_default: [],
                         fields_by_name: { part:  instance_double('Field', name: :part,  type: :string),
                                           title: instance_double('Field', name: :title, type: :string) })
    end

    # Input and slug order disagree within part "a"; Alpha sorts last by part.
    let(:entries) do
      [{ content_type_id: 1, _position: 0, _label: 'Alpha', part: 'b' },
       { content_type_id: 1, _position: 1, _label: 'Zulu',  part: 'a' },
       { content_type_id: 1, _position: 2, _label: 'Mike',  part: 'a' }]
    end

    it 'follows the type default and breaks its tie by slug' do
      expect(repository.with(type).all.map { |entry| entry._slug[:en] }).to eq %w(mike zulu alpha)
    end

  end

  describe '#conditions_without_order_by' do

    let(:conditions) { {} }

    subject { repository.with(type).send(:conditions_without_order_by, conditions) }

    def prepared_for(conditions)
      repository.with(type).send(:conditions_without_order_by, conditions).first
    end

    it { is_expected.to eq([{ '_visible' => true, 'content_type_id' => 1 }, nil]) }

    context 'select fields' do

      let(:value)       { 'CMS' }
      let(:option)      { instance_double('Option', _id: 42)}
      let(:options)     { instance_double('OptionRepository', by_name: option, :'locale=' => nil) }
      let(:field)       { instance_double('SelectField', name: 'category', persisted_name: 'category_id', select_options: options) }
      let(:_fields)     { instance_double('Fields', selects: [field], belongs_to: [], many_to_many: [], dates_and_date_times: [], numbers: [], booleans: []) }
      let(:conditions)  { { 'category' => value } }

      it { is_expected.to eq([{ '_visible' => true, 'content_type_id' => 1, 'category_id' => 42 }, nil]) }

      context 'an operator whose operand is not a field value' do
        let(:conditions) { { 'category.exists' => true } }

        it 'still maps the field to its persisted name' do
          expect(subject.first).to include('category_id.exists' => true)
        end
      end

    end

    context 'date fields' do

      let(:value)       { '2009/09/10' }
      let(:field)       { instance_double('DateField', name: 'launched_at', persisted_name: 'launched_at', type: :date) }
      let(:_fields)     { instance_double('Fields', selects: [], belongs_to: [], many_to_many: [], dates_and_date_times: [field], numbers: [], booleans: []) }
      let(:conditions)  { { 'launched_at' => value } }

      it { is_expected.to eq([{ '_visible' => true, 'content_type_id' => 1, 'launched_at' => Date.parse('2009/09/10') }, nil]) }

    end

    context 'date time fields' do

      before { Time.zone = 'Paris' }

      let(:value)       { '2007-06-29T21:15:00' }
      let(:field)       { instance_double('DateField', name: 'launched_at', persisted_name: 'launched_at', type: :date_time) }
      let(:_fields)     { instance_double('Fields', selects: [], belongs_to: [], many_to_many: [], dates_and_date_times: [field], numbers: [], booleans: []) }
      let(:conditions)  { { 'launched_at' => value } }

      # Time.zone belongs to whatever request is running; the site decides.
      it 'reads an offset-less time in the site zone, not the process one' do
        expect(subject.first['launched_at']).to eql Time.utc(2007, 6, 29, 21, 15)
      end

      context 'a site behind UTC' do
        let(:site) do
          instance_double('Site', _id: 1, default_locale: :en, locales: %i(en fr),
                          timezone: ActiveSupport::TimeZone['America/New_York'])
        end

        it { expect(subject.first['launched_at']).to eql Time.utc(2007, 6, 30, 1, 15) }

        # A calendar date names a day; the site decides which instant it is.
        context 'given a Date' do
          let(:value) { Date.new(2013, 2, 11) }

          it { expect(subject.first['launched_at']).to eql Time.utc(2013, 2, 11, 5) }
        end
      end

      it 'keeps the instant an operand spells its own offset for' do
        expect(described_class.new(adapter, site, locale, content_type_repository)
                 .with(type).send(:conditions_without_order_by, 'launched_at' => '2007-06-29T21:15:00Z')
                 .first['launched_at'])
          .to eql Time.utc(2007, 6, 29, 21, 15)
      end

      context 'surrounded by whitespace' do
        let(:value) { "\t2019-09-10T10:30:00Z\n" }

        it { expect(subject.first['launched_at']).to eql Time.utc(2019, 9, 10, 10, 30) }
      end

      # The slash form belongs to a date, and a date and time joins them with T.
      ['2007/06/29', '2007/06/29 21:15:00', '2007-06-29 21:15:00'].each do |rejected|
        context rejected.inspect do
          let(:value) { rejected }
          it { expect(subject.first['launched_at']).to eq Locomotive::Steam::Adapters::Query::Values.unmatchable }
        end
      end

    end

    context 'date fields' do

      before { Time.zone = 'Paris' }

      let(:field)       { instance_double('DateField', name: 'held_on', persisted_name: 'held_on', type: :date) }
      let(:_fields)     { instance_double('Fields', selects: [], belongs_to: [], many_to_many: [], dates_and_date_times: [field], numbers: [], booleans: []) }
      let(:conditions)  { { 'held_on' => value } }

      # The documented with_scope example spells a date with slashes.
      ['2012-01-02', '2012/01/02', ' 2012/01/02 '].each do |written|
        context written.inspect do
          let(:value) { written }
          it { expect(subject.first['held_on']).to eq Date.new(2012, 1, 2) }
        end
      end

      ['2012-01-02T10:00:00', 'tomorrow', '2012-99-99', ''].each do |bad|
        context bad.inspect do
          let(:value) { bad }
          it { expect(subject.first['held_on']).to eq Locomotive::Steam::Adapters::Query::Values.unmatchable }
        end
      end

    end

    context 'boolean fields' do

      let(:field)       { instance_double('BooleanField', name: 'flag', persisted_name: 'flag', type: :boolean) }
      let(:_fields)     { instance_double('Fields', selects: [], belongs_to: [], many_to_many: [], dates_and_date_times: [], numbers: [], booleans: [field]) }
      let(:conditions)  { { 'flag' => value } }

      { true => true, false => false, 'true' => true, ' TRUE ' => true,
        'false' => false, 'False' => false, '1' => true, '0' => false }.each do |written, expected|
        context written.inspect do
          let(:value) { written }
          it { expect(subject.first['flag']).to eq expected }
        end
      end

      # Ruby truthiness is not the grammar: only the listed forms read.
      ['yes', 'on', '', 1, 0, 1.0].each do |bad|
        context bad.inspect do
          let(:value) { bad }

          it do
            if bad.is_a?(String)
              expect(subject.first['flag']).to eq Locomotive::Steam::Adapters::Query::Values.unmatchable
            else
              expect { subject }.to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
            end
          end
        end
      end

      context 'a list operand' do
        let(:conditions) { { 'flag.in' => ['1', 'nope'] } }

        it 'reads every element' do
          expect(subject.first['flag.in']).to eq [true, Locomotive::Steam::Adapters::Query::Values.unmatchable]
        end
      end

    end

    context 'an _id list operand' do

      before { allow(adapter).to receive(:make_id) { |id| "id-#{id}" } }

      it 'converts every id in an Array' do
        expect(prepared_for('_id.in' => %w(a b))).to include('_id.in' => %w(id-a id-b))
      end

      it 'converts a Set the same way' do
        expect(prepared_for('_id.in' => Set['a'])).to include('_id.in' => %w(id-a))
      end

    end

    context 'select fields carrying a list or an unknown option' do

      let(:option)  { instance_double('Option', _id: 42) }
      let(:options) { instance_double('OptionRepository', :'locale=' => nil) }
      let(:field)   { instance_double('SelectField', name: 'category', persisted_name: 'category_id', select_options: options) }
      let(:_fields) { instance_double('Fields', selects: [field], belongs_to: [], many_to_many: [], dates_and_date_times: [], numbers: [], booleans: []) }

      before do
        allow(options).to receive(:by_name) { |name| name == 'CMS' ? option : nil }
      end

      it 'converts the elements of a list operand' do
        expect(prepared_for('category.in' => %w(CMS)))
          .to include('category_id.in' => [42])
      end

      it 'converts the elements of a Set operand' do
        expect(prepared_for('category.in' => Set['CMS']))
          .to include('category_id.in' => [42])
      end

      it 'leaves a non-field operand for its own kind to judge' do
        expect(prepared_for('category.exists' => /x/)).to include('category_id.exists' => /x/)
      end

      it 'maps an unknown option name to the unmatchable sentinel, not nil' do
        expect(prepared_for('category' => 'nope'))
          .to include('category_id' => Locomotive::Steam::Adapters::Query::Values.unmatchable)
      end

      it 'maps an unknown option name inside a list the same way' do
        expect(prepared_for('category.nin' => %w(CMS nope)))
          .to include('category_id.nin' => [42, Locomotive::Steam::Adapters::Query::Values.unmatchable])
      end

      it 'still resolves a nil operand to nil' do
        expect(prepared_for('category' => nil)).to include('category_id' => nil)
      end

    end

    context 'date fields carrying a plain-field expression or a list' do

      let(:field)   { instance_double('DateField', name: 'launched_at', persisted_name: 'launched_at', type: :date) }
      let(:_fields) { instance_double('Fields', selects: [], belongs_to: [], many_to_many: [], dates_and_date_times: [field], numbers: [], booleans: []) }

      it 'leaves a Range untouched' do
        range = Date.new(2012, 1, 1)..Date.new(2012, 12, 31)
        expect(prepared_for('launched_at' => range)).to include('launched_at' => range)
      end

      it 'leaves a Regexp untouched' do
        expect(prepared_for('launched_at' => /2012/)).to include('launched_at' => /2012/)
      end

      it 'converts the elements of a list operand' do
        expect(prepared_for('launched_at.in' => %w(2012-06-29)))
          .to include('launched_at.in' => [Date.new(2012, 6, 29)])
      end

      it 'converts the elements of a Set operand' do
        expect(prepared_for('launched_at.in' => Set['2012-06-29']))
          .to include('launched_at.in' => [Date.new(2012, 6, 29)])
      end

      it 'rejects an unsupported value kind' do
        [true, { 'a' => 1 }].each do |bad|
          expect { prepared_for('launched_at' => bad) }
            .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
        end
      end

      context 'on a date time field' do

        let(:field) { instance_double('DateField', name: 'launched_at', persisted_name: 'launched_at', type: :date_time) }

        it 'rejects a value that cannot convert to a date time' do
          expect { prepared_for('launched_at' => double('DateOnly', to_date: Date.new(2012, 1, 1))) }
            .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
        end

      end

    end

    context 'ISO dash date' do

      let(:value)       { '2019-09-10' }
      let(:field)       { instance_double('DateField', name: 'launched_at', persisted_name: 'launched_at', type: :date) }
      let(:_fields)     { instance_double('Fields', selects: [], belongs_to: [], many_to_many: [], dates_and_date_times: [field], numbers: [], booleans: []) }
      let(:conditions)  { { 'launched_at' => value } }

      it { is_expected.to eq([{ '_visible' => true, 'content_type_id' => 1, 'launched_at' => Date.new(2019, 9, 10) }, nil]) }

    end

    context 'ISO date time with a UTC offset' do

      let(:value)       { '2007-06-29T21:15:00+00:00' }
      let(:field)       { instance_double('DateField', name: 'launched_at', persisted_name: 'launched_at', type: :date_time) }
      let(:_fields)     { instance_double('Fields', selects: [], belongs_to: [], many_to_many: [], dates_and_date_times: [field], numbers: [], booleans: []) }
      let(:conditions)  { { 'launched_at' => value } }

      it { is_expected.to eq([{ '_visible' => true, 'content_type_id' => 1, 'launched_at' => Time.utc(2007, 6, 29, 21, 15) }, nil]) }

    end

    context 'date-only value for a date-time field resolves to midnight' do

      before { Time.zone = 'UTC' }

      let(:value)       { '2019-09-10' }
      let(:field)       { instance_double('DateField', name: 'launched_at', persisted_name: 'launched_at', type: :date_time) }
      let(:_fields)     { instance_double('Fields', selects: [], belongs_to: [], many_to_many: [], dates_and_date_times: [field], numbers: [], booleans: []) }
      let(:conditions)  { { 'launched_at' => value } }

      it { is_expected.to eq([{ '_visible' => true, 'content_type_id' => 1, 'launched_at' => Time.utc(2019, 9, 10) }, nil]) }

    end

    context 'invalid date strings match nothing' do

      let(:field)       { instance_double('DateField', name: 'launched_at', persisted_name: 'launched_at', type: :date_time) }
      let(:_fields)     { instance_double('Fields', selects: [], belongs_to: [], many_to_many: [], dates_and_date_times: [field], numbers: [], booleans: []) }
      let(:conditions)  { { 'launched_at' => value } }

      ['tomorrow', '2025-99-99', ''].each do |bad|
        context bad.inspect do
          let(:value) { bad }
          it { expect(subject.first['launched_at']).to eq Locomotive::Steam::Adapters::Query::Values.unmatchable }
        end
      end

    end

    context 'numeric fields' do

      let(:field_type)  { :float }
      let(:field)       { instance_double('NumberField', name: 'price', persisted_name: 'price', type: field_type) }
      let(:_fields)     { instance_double('Fields', selects: [], belongs_to: [], many_to_many: [], dates_and_date_times: [], numbers: [field], booleans: []) }
      let(:conditions)  { { 'price.lt' => value } }

      def prepared
        subject.first['price.lt']
      end

      def subject_for(conditions)
        repository.with(type).send(:conditions_without_order_by, conditions).first
      end

      context 'a String from params' do
        let(:value) { '42.5' }
        it { expect(prepared).to eq 42.5 }

        context 'on an integer field' do
          let(:field_type) { :integer }
          let(:value)      { '42' }
          it { expect(prepared).to eq 42 }
        end
      end

      context 'a value that is already numeric' do
        let(:value) { 42.5 }
        it { expect(prepared).to eq 42.5 }
      end

      context 'a nil value' do
        let(:value) { nil }
        it { expect(prepared).to be_nil }
      end

      context 'a list operand' do
        let(:conditions) { { 'price.in' => %w(1 2) } }
        it { expect(subject.first['price.in']).to eq [1.0, 2.0] }

        it 'does not mutate the given array' do
          source = %w(1 2)
          repository.with(type).send(:conditions_without_order_by, 'price.in' => source)
          expect(source).to eq %w(1 2)
        end
      end

      context 'a Range — its own plain-field expression, not an operand' do
        let(:conditions) { { 'price' => (5..6) } }
        it { expect(subject.first['price']).to eq(5..6) }
      end

      context 'two conditions bounding the same field' do
        let(:conditions) { { 'price.gte' => '5', 'price.lte' => '10' } }
        it 'converts both, not only the last one' do
          expect(subject.first).to include('price.gte' => 5.0, 'price.lte' => 10.0)
        end
      end

      context 'operators that carry no field value' do
        it 'leaves the exists operand to the operator registry' do
          expect(subject_for('price.exists' => true)).to include('price.exists' => true)
        end

        it 'leaves the size operand to the operator registry' do
          expect(subject_for('price.size' => '2')).to include('price.size' => '2')
        end
      end

      context 'a String no number can equal — a visitor typed it' do
        %w(abc 4.2.1).each do |bad|
          context bad.inspect do
            let(:value) { bad }
            it('matches nothing, and is never turned into nil') { expect(prepared).to eq Locomotive::Steam::Adapters::Query::Values.unmatchable }
          end
        end

        context 'a fractional string on an integer field' do
          let(:field_type) { :integer }
          let(:value)      { '4.2' }
          it { expect(prepared).to eq Locomotive::Steam::Adapters::Query::Values.unmatchable }
        end

        it 'reads only what is numeric inside a list' do
          expect(subject_for('price.in' => ['1', 'abc'])).to include('price.in' => [1.0, Locomotive::Steam::Adapters::Query::Values.unmatchable])
        end

        it 'does not confuse it with a real nil, which means missing or null' do
          expect(subject_for('price.in' => [nil, '1'])).to include('price.in' => [nil, 1.0])
          expect(subject_for('price' => 'abc')).to include('price' => Locomotive::Steam::Adapters::Query::Values.unmatchable)
        end
      end

      context 'the decimal grammar a numeric string has to meet' do

        it 'reads a number through surrounding whitespace' do
          expect(subject_for('price.lt' => ' 10 ')).to include('price.lt' => 10.0)
          expect(subject_for('price.lt' => "\t-10\n")).to include('price.lt' => -10.0)
        end

        it 'reads the sign, fraction and exponent it allows' do
          expect(subject_for('price.lt' => '+1.5e2')).to include('price.lt' => 150.0)
          expect(subject_for('price.lt' => '-.5')).to include('price.lt' => -0.5)
        end

        # Ruby 3.3 rejects a trailing dot where 3.4 reads 5.0, so the grammar
        # cannot accept it without meaning different things on each.
        ['1_5', '0x1', '1 0', '1e9999', '5.', '  ', ''].each do |bad|
          it "matches nothing for #{bad.inspect}" do
            expect(subject_for('price.lt' => bad)).to include('price.lt' => Locomotive::Steam::Adapters::Query::Values.unmatchable)
          end
        end

        context 'on an integer field' do
          let(:field_type) { :integer }

          it 'reads a plain decimal' do
            expect(subject_for('price.lt' => ' +42 ')).to include('price.lt' => 42)
          end

          ['1_5', '4.2', '0x1'].each do |bad|
            it "matches nothing for #{bad.inspect}" do
              expect(subject_for('price.lt' => bad)).to include('price.lt' => Locomotive::Steam::Adapters::Query::Values.unmatchable)
            end
          end

          it 'matches nothing for an out of range integer' do
            [2**63, -2**63 - 1].map(&:to_s).each do |beyond|
              expect(subject_for('price.lt' => beyond)).to include('price.lt' => Locomotive::Steam::Adapters::Query::Values.unmatchable)
            end
          end
        end

      end

      context 'a typed number outside the supported domain' do

        it 'rejects an integer beyond either end of int64' do
          [2**63, -2**63 - 1].each do |bad|
            expect { subject_for('price.lt' => bad) }
              .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
          end
        end

        it 'accepts an integer at either end of int64' do
          [2**63 - 1, -2**63].each do |edge|
            expect(subject_for('price.lt' => edge)).to include('price.lt' => edge)
          end
        end

        it 'rejects a float that is not finite' do
          [Float::INFINITY, -Float::INFINITY, Float::NAN].each do |bad|
            expect { subject_for('price.lt' => bad) }
              .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
          end
        end

        # BSON stores it as a Decimal128; the bounds above do not apply.
        it 'passes a BigDecimal through untouched' do
          expect(subject_for('price.lt' => BigDecimal('1.5')))
            .to include('price.lt' => BigDecimal('1.5'))
        end

      end

      context 'an unsupported value kind' do
        it 'raises' do
          [{ 'a' => 1 }, true].each do |bad|
            expect { subject_for('price.lt' => bad) }
              .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
          end
        end
      end

      context 'a key outside the closed grammar' do
        it 'is rejected rather than silently truncated' do
          expect { subject_for('price.gt.extra' => 5) }
            .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
        end
      end

    end

    context 'belongs_to fields' do

      let(:value)       { 42 }
      let(:field)       { instance_double('BelongsToField', name: 'person', persisted_name: 'person_id', target_id: '42') }
      let(:_fields)     { instance_double('Fields', selects: [], belongs_to: [field], many_to_many: [], dates_and_date_times: [], numbers: [], booleans: []) }
      let(:conditions)  { { 'person' => value } }

      it { is_expected.to eq([{ '_visible' => true, 'content_type_id' => 1, 'person_id' => 42 }, nil]) }

      context 'the target value is a content entry' do

        let(:value) { instance_double('TargetContentEntry', _id: 1) }

        it { is_expected.to eq([{ '_visible' => true, 'content_type_id' => 1, 'person_id' => 1 }, nil]) }

      end

      context 'the target is a hash' do

        let(:value) { { '_id' => 42 } }

        it { is_expected.to eq([{ '_visible' => true, 'content_type_id' => 1, 'person_id' => 42 }, nil]) }

      end

      context 'the target value is an arry of content entry' do

        let(:value) { [instance_double('TargetContentEntry', _id: 1), instance_double('TargetContentEntry', _id: 2)] }
        let(:conditions)  { { 'person.in' => value } }

        it { is_expected.to eq([{ '_visible' => true, 'content_type_id' => 1, 'person_id.in' => [1, 2] }, nil]) }

      end

      context 'testing a nil value (field => nil)' do

        let(:value) { nil }
        it { is_expected.to eq([{ '_visible' => true, 'content_type_id' => 1, 'person_id' => nil }, nil]) }

      end

      context 'testing a nil value (field.ne => nil)' do

        let(:conditions)  { { 'person.ne' => nil } }
        it { is_expected.to eq([{ '_visible' => true, 'content_type_id' => 1, 'person_id.ne' => nil }, nil]) }

      end

    end

    context 'many_to_many fields' do

      let(:value)       { 42 }
      let(:field)       { instance_double('ManyToManyField', name: 'tags', persisted_name: 'tag_ids', target_id: '42') }
      let(:_fields)     { instance_double('Fields', selects: [], belongs_to: [], many_to_many: [field], dates_and_date_times: [], numbers: [], booleans: []) }
      let(:conditions)  { { 'tags.in' => value } }

      it { is_expected.to eq([{ '_visible' => true, 'content_type_id' => 1, 'tag_ids.in' => [42] }, nil]) }

      context 'the documented all form, once the parser has normalized it' do

        let(:conditions) { { 'tags.all' => %w(A B) } }

        it 'resolves every element to an id under the persisted name' do
          expect(subject.first).to include('tag_ids.all' => %w(A B))
        end

      end

      context 'the target value is a content entry' do

        let(:value) { [instance_double('TargetContentEntry', _id: 1), 42] }

        it { is_expected.to eq([{ '_visible' => true, 'content_type_id' => 1, 'tag_ids.in' => [1, 42] }, nil]) }

      end

    end

  end

  # ContentType#fields_by_name is indifferent; the double has to be too.
  def build_content_type(name, attributes = {})
    defaults = {
      _id:                    1,
      slug:                   name.to_s.downcase,
      order_by:               nil,
      localized_names:        [],
      association_fields:     [],
      fields_by_name:         {}
    }

    attributes = defaults.merge(attributes)
    attributes[:fields_by_name] = attributes[:fields_by_name].with_indifferent_access

    instance_double(name, attributes)
  end

end
