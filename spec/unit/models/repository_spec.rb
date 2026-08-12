require 'spec_helper'

describe Locomotive::Steam::Models::Repository do

  let(:adapter)     { nil }
  let(:site)        { nil }
  let(:locale)      { :en }
  let(:repository)  { ArticleRepository.new(adapter, site, locale) }

  describe '#locale' do

    subject { repository.locale }

    it { is_expected.to eq :en }

    context 'change the locale' do

      before { repository.locale = :fr }

      it { is_expected.to eq :fr }

    end

  end

  describe '#scope' do

    subject { repository.scope }

    it { expect(subject.locale).to eq :en }

    context 'change the locale from the repository' do

      before { subject; repository.locale = :fr }

      it { expect(subject.locale).to eq :fr }

    end

  end

  describe '#all' do

    let(:dataset) { double('dataset') }

    it 'materializes the query result' do
      allow(repository).to receive(:query).and_return(dataset)
      allow(dataset).to receive(:all).and_return([:entity])

      expect(repository.all).to eq [:entity]
      expect(dataset).to have_received(:all)
    end

  end

  describe '#dup' do

    subject(:copy) { repository.dup }

    it 'gives the copy its own scope' do
      expect(copy.scope).not_to be(repository.scope)
    end

    it 'isolates the copy scope context from the original' do
      repository.scope.context[:content_type] = :parent
      copy.scope.context[:content_type] = :child

      expect(repository.scope.context[:content_type]).to eq :parent
    end

    it 'gives the copy its own mapper (not the source one)' do
      source_mapper = repository.mapper

      expect(copy.mapper).not_to be(source_mapper)
    end

  end

  class ArticleRepository
    include Locomotive::Steam::Models::Repository
    mapping :articles
  end

end
