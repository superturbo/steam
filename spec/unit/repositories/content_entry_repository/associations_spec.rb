require 'spec_helper'

require_relative '../../../support/content_entry_repository_context'

describe Locomotive::Steam::ContentEntryRepository do

  include_context 'content entry repository'

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
      let(:type) { build_content_type('Articles', label_field_name: :title, localized_names: %w(title), fields: _fields, fields_by_name: { articles: instance_double('Field', type: :has_many) }, fields_with_default: []) }
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
      allow(adapter).to receive(:collection).and_return(loaded(other_entries))
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
      allow(adapter).to receive(:collection).and_return(loaded(other_entries))
      expect(articles.all.map(&:title)).to eq ['Lorem ipsum', 'Hello world']
    end

    it 'applies a runtime order_by to the returned entries (over the field default)' do
      articles = repository.value_for(subject, :articles, order_by: 'title.asc')
      allow(adapter).to receive(:collection).and_return(loaded(other_entries))

      expect(articles.all.map(&:title)).to eq ['Hello world', 'Lorem ipsum']
    end

    it 'applies a runtime order_by given as a hash (symbol direction)' do
      articles = repository.value_for(subject, :articles, order_by: { title: :asc })
      allow(adapter).to receive(:collection).and_return(loaded(other_entries))

      expect(articles.all.map(&:title)).to eq ['Hello world', 'Lorem ipsum']
    end

    it 'does not leak a scoped copy back into the original association' do
      scoped = repository.value_for(subject, :articles, order_by: 'title.asc')
      allow(adapter).to receive(:collection).and_return(loaded(other_entries))
      scoped.all

      expect(subject.articles.all.map(&:title)).to eq ['Lorem ipsum', 'Hello world']
    end

    it 'does not change the parent scope content type when the association loads' do
      articles = subject.articles
      allow(adapter).to receive(:collection).and_return(loaded(other_entries))
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
        allow(adapter).to receive(:collection).and_return(loaded(other_entries))
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
      allow(adapter).to receive(:collection).and_return(loaded(other_entries))
      expect(articles.all.map(&:title)).to eq ['Hello world', 'Lorem ipsum']
    end

    it 'applies a runtime order_by to the returned entries' do
      articles = repository.value_for(subject, :articles, order_by: 'title.desc')
      allow(adapter).to receive(:collection).and_return(loaded(other_entries))

      expect(articles.all.map(&:title)).to eq ['Lorem ipsum', 'Hello world']
    end

    it 'does not leak a scoped copy back into the original association' do
      scoped = repository.value_for(subject, :articles, order_by: 'title.desc')
      allow(adapter).to receive(:collection).and_return(loaded(other_entries))
      scoped.all

      expect(subject.articles.all.map(&:title)).to eq ['Hello world', 'Lorem ipsum']
    end

  end

end
