require 'spec_helper'

describe Locomotive::Steam::Models::Mapper do

  let(:adapter)        { instance_double('Adapter') }
  let(:locale)         { :en }
  let(:default_locale) { :en }
  let(:scope)          { instance_double('SimpleScope', apply: true, locale: locale, default_locale: default_locale) }
  let(:repository)     { instance_double('Repository', scope: scope, base_url: '') }
  let(:name)           { 'pages' }
  let(:options)        { { entity: MyPage } }
  let(:block)          { nil }
  let(:mapper)         { described_class.new(name, options, repository, &block) }

  describe '#localized attributes' do

    let(:block) { ->(_) { localized_attributes(:foo, :bar) } }

    subject { mapper.localized_attributes }
    it { is_expected.to eq [:foo, :bar] }

  end

  describe '#serialize' do

    let(:options) { { entity: MyArticle } }
    let(:attributes) { { title: 'Hello world', body: 'Lorem ipsum', published_at: DateTime.parse('2007/06/29 00:00:00') } }
    let(:entity) { mapper.to_entity(attributes) }

    subject { mapper.serialize(entity) }

    it { expect(subject).to eq('title' => 'Hello world', 'body' => 'Lorem ipsum', 'published_at' => DateTime.parse('2007/06/29 00:00:00')) }

    describe 'a value read in every locale but kept in none' do

      let(:block)      { ->(_) { localized_attributes(:title, :category); virtual_attributes(:category) } }
      let(:attributes) { { title: { 'en' => 'Hello world' }, category_id: 42 } }

      it 'hands over what the entity holds, without it' do
        expect(subject).to eq('title' => { 'en' => 'Hello world' }, 'category_id' => 42)
      end

    end

    describe 'association' do

      let(:repository)  { instance_double('AuthorRepository', scope: scope, adapter: adapter, base_url: '') }

      describe 'belongs_to' do

        let(:block) { ->(_) { belongs_to_association(:author, BlankRepository) } }

        context 'no object' do

          let(:attributes) { { author_id: nil } }

          it { expect(subject).to eq('author_id' => nil) }

        end

        context 'existing object' do

          before { entity.author = instance_double('Author', _id: 1) }

          it { expect(subject).to eq('title' => 'Hello world', 'author_id' => 1, 'body' => 'Lorem ipsum', 'published_at' => DateTime.parse('2007/06/29 00:00:00')) }

        end

      end

      describe 'many_to_many' do

        let(:block) { ->(_) { many_to_many_association(:authors, BlankRepository) } }

        context 'no object' do

          let(:attributes) { { author_ids: nil } }

          it { expect(subject).to eq('author_ids' => nil) }

        end

        context 'existing object' do

          before { entity.authors = [instance_double('Author', _id: 1), instance_double('Author', _id: 2)] }

          it { expect(subject).to eq('title' => 'Hello world', 'author_ids' => [1, 2], 'body' => 'Lorem ipsum', 'published_at' => DateTime.parse('2007/06/29 00:00:00')) }

        end

      end

    end

    describe 'localized attributes' do
      let(:block) { ->(_) { localized_attributes(:title) } }
      let(:attributes) { { title: { fr: 'Bonjour' }, body: 'Lorem ipsum', published_at: DateTime.parse('2007/06/29 00:00:00') } }
      it { expect(subject).to eq('title' => { 'fr' => 'Bonjour' }, 'body' => 'Lorem ipsum', 'published_at' => DateTime.parse('2007/06/29 00:00:00')) }
    end
  end

  describe 'after_load' do

    let(:attributes) { { title: 'Hello world' } }
    let(:repository) { instance_double('Repository', my_site: 42, base_url: '') }
    let(:seen)       { [] }
    let(:block) do
      recorder = seen
      ->(_) {
        default_attribute(:site, -> (repository) { repository.my_site })
        after_load { |entity, repository| recorder << [entity.site, repository] }
      }
    end

    it 'runs on an entity read out of a store' do
      entity = mapper.to_entity(attributes)

      expect(seen).to eq [[42, repository]]
      expect(entity.site).to eq 42
    end

    it 'does not run on an entity the caller builds' do
      mapper.build_entity(attributes)

      expect(seen).to be_empty
    end

    describe 'sharing an id with the identity map' do

      let(:attributes) { { _id: 7, title: 'Hello world' } }

      it 'still runs after a caller built an entity with that id' do
        mapper.build_entity(attributes)
        mapper.to_entity(attributes)

        expect(seen.size).to eq 1
      end

      it 'leaves the build path its own entity' do
        stored = mapper.to_entity(attributes)

        expect(mapper.build_entity(attributes)).not_to be(stored)
      end

      it 'runs once for an entity the store hands back twice' do
        expect(mapper.to_entity(attributes)).to be(mapper.to_entity(attributes))
        expect(seen.size).to eq 1
      end

    end

  end

  describe '#to_entity' do

    subject { mapper.to_entity(attributes) }

    describe 'default attributes' do

      let(:attributes) { { title: 'Hello world' } }
      let(:repository) { instance_double('Repository', my_site: 42, base_url: '') }
      let(:block) { ->(_) { default_attribute(:site, -> (repository) { repository.my_site }) } }

      it { expect(subject.site).to eq 42 }

    end

    describe 'association' do

      let(:repository)  { instance_double('Repository', scope: 42, base_url: '') }
      let(:attributes) { { parents: [instance_double('Page', title: 'Hello world')] } }
      let(:klass) { instance_double('RepositoryKlass')}
      let(:block) { ->(_) { embedded_association(:parents, BlankRepository) } }

      it { expect(subject.parents).not_to eq nil }

    end

    describe 'localized attributes' do

      let(:block) { ->(_) { localized_attributes(:title) } }
      let(:attributes) { { title: { 'en' => 'Hello world' } } }

      it { expect(subject.attributes[:title].class).to eq Locomotive::Steam::Models::I18nField }
      it { expect(subject.attributes[:title][:en]).to eq('Hello world') }

      context 'string value for the localized field' do

        let(:attributes) { { title: 'Hello world' } }

        it { expect(subject.attributes[:title][:en]).to eq('Hello world') }
        it { expect(subject.attributes[:title][:fr]).to eq('Hello world') }

      end

    end

  end

  describe '#build_entity' do

    let(:block)      { ->(_) { localized_attributes(:title) } }
    let(:attributes) { { title: 'Hello world' } }

    subject { mapper.build_entity(attributes) }

    describe 'localized attributes' do

      it 'writes a lone value into the locale it was built in' do
        expect(subject.attributes[:title].translations).to eq('en' => 'Hello world')
      end

      context 'with no locale of its own' do

        let(:locale)         { nil }
        let(:default_locale) { :fr }

        it 'writes it into the one the site reads by default' do
          expect(subject.attributes[:title].translations).to eq('fr' => 'Hello world')
        end

        context 'and no site to name one' do

          let(:default_locale) { nil }

          it { expect { subject }.to raise_error(Locomotive::Steam::MissingLocale) }

        end

      end

      context 'given a value per locale' do

        let(:attributes) { { title: { 'en' => 'Hello world', 'fr' => 'Bonjour monde' } } }

        it { expect(subject.attributes[:title].translations).to eq('en' => 'Hello world', 'fr' => 'Bonjour monde') }

      end

      context 'given no value' do

        let(:attributes) { { title: nil } }

        it { expect(subject.attributes[:title].translations).to eq({}) }

      end

    end

  end

  class MyPage
    include Locomotive::Steam::Models::Entity
    attr_accessor :site
  end

  class MyArticle
    include Locomotive::Steam::Models::Entity
    attr_accessor :site
  end

  class BlankRepository < Struct.new(:adapter)
    attr_accessor :page, :scope
  end

end
