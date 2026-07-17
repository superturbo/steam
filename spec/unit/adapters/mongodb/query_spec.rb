require 'spec_helper'

require_relative '../../../../lib/locomotive/steam/adapters/mongodb/query.rb'

describe Locomotive::Steam::Adapters::MongoDB::Query do

  let(:site)  { instance_double('Site', _id: 42) }
  let(:scope) { instance_double('Scope', locale: :en, site: site) }
  let(:localized_attributes) { [:title] }
  let(:block) { nil }

  let(:query) { Locomotive::Steam::Adapters::MongoDB::Query.new(scope, localized_attributes, &block) }

  describe '#where' do

    let(:criterion) { { fullpath: 'index' } }

    context 'simple call' do

      before { query.where(criterion) }

      it { expect(query.criteria).to eq({ fullpath: 'index' }) }

    end

    context 'chained' do

      let(:another_criterion) { { published: true } }

      before { query.where(criterion).where(another_criterion) }

      it { expect(query.criteria).to eq({ fullpath: 'index', published: true }) }

    end

  end

  describe '#order_by (decoded to the neutral form)' do

    subject { query.order_by(order_by).sort }

    context 'passing a hash' do

      let(:order_by) { { title: :asc, published: :desc } }

      it { is_expected.to eq [[:title, :asc], [:published, :desc]] }

    end

    context 'passing a string' do

      let(:order_by) { 'title.asc, published' }

      it { is_expected.to eq [[:title, :asc], [:published, :asc]] }

    end

    context 'passing an array of pairs' do

      let(:order_by) { [['title', 'asc'], ['published', 'desc']] }

      it { is_expected.to eq [[:title, :asc], [:published, :desc]] }

    end

  end

  describe 'chaining where and order_by' do

    before { query.where(published: true).order_by(title: :asc) }

    it { expect(query.criteria).to eq({ published: true }) }
    it { expect(query.sort).to eq([[:title, :asc]]) }

  end

  describe '#against' do

    let(:collection) { instance_double('Mongo::Collection') }
    let(:view)       { instance_double('Mongo::Collection::View') }

    before { allow(collection).to receive(:find).and_return(view) }

    context 'tenant boundary' do

      it 'scopes an empty query to the current site, with no options' do
        query.against(collection)
        expect(collection).to have_received(:find).with({ 'site_id' => 42 }, {})
      end

      it 'cannot be widened by a user-supplied site_id criterion' do
        query.where('site_id.ne' => 42).against(collection)
        expect(collection).to have_received(:find).with(
          { '$and' => [{ 'site_id' => { '$ne' => 42 } }, { 'site_id' => 42 }] }, {}
        )
      end

      context 'without a current site' do

        let(:site) { nil }

        it 'does not add a site filter' do
          query.where(handle: 'acme').against(collection)
          expect(collection).to have_received(:find).with({ 'handle' => 'acme' }, {})
        end

      end

    end

    it 'passes sort, projection, skip and limit as find options' do
      query.only(:title, :published).order_by(title: :asc).offset(5).limit(10).against(collection)
      expect(collection).to have_received(:find).with(
        { 'site_id' => 42 },
        { sort: { 'title.en' => 1 }, projection: { 'title.en' => 1, 'published' => 1 }, skip: 5, limit: 10 }
      )
    end

  end

end
