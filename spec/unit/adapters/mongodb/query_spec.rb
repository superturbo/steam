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

      it { expect(query.criteria).to eq [[:fullpath, 'index']] }

    end

    context 'chained' do

      let(:another_criterion) { { published: true } }

      before { query.where(criterion).where(another_criterion) }

      it { expect(query.criteria).to eq [[:fullpath, 'index'], [:published, true]] }

    end

    context 'twice on the same field' do

      before { query.where(fullpath: 'index').where(fullpath: 'about') }

      it 'keeps both, since each one still has to be met' do
        expect(query.criteria).to eq [[:fullpath, 'index'], [:fullpath, 'about']]
      end

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

    it { expect(query.criteria).to eq [[:published, true]] }
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

  describe '#in_id_order' do

    let(:finds)   { [] }
    let(:counted) { [] }
    let(:responses) { [] }

    let(:collection) do
      double('Collection').tap do |collection|
        allow(collection).to receive(:find) do |filter, options = {}|
          finds << [filter, options]
          responses.shift || []
        end
        allow(collection).to receive(:count_documents) do |filter|
          counted << filter
          0
        end
      end
    end

    def doc(id, name = id.upcase)
      { '_id' => id, 'name' => name }
    end

    # Outermost first; a windowed fetch adds its narrower bound last.
    def id_bounds(filter)
      return [filter.dig('_id', '$in')] if filter.key?('_id')

      (filter['$and'] || []).flat_map { |clause| id_bounds(clause) }
    end

    it 'sends nothing to the store until the result is consumed' do
      query.in_id_order(%w(a b)).against(collection)

      expect(finds).to be_empty
      expect(counted).to be_empty
    end

    it 'reads an unbounded list once and follows the given order' do
      responses << [doc('a'), doc('b')]

      view = query.where(published: true).in_id_order(%w(b a x b)).against(collection)

      expect(view.map { |document| document['_id'] }).to eq %w(b a)
      expect(finds.length).to eq 1
      expect(id_bounds(finds[0].first)).to eq [%w(b a x)]
      expect(finds[0].first.to_s).to include('published')
      expect(finds[0].first.to_s).to include('site_id')
      expect(finds[0].last).not_to include(:sort, :skip, :limit)
    end

    it 'projects the IDs first and fetches only the window through the whole filter' do
      responses << [doc('a'), doc('b'), doc('c')]
      responses << [doc('a')]

      view = query.where(published: true).in_id_order(%w(c a b)).offset(1).limit(1).against(collection)

      expect(view.map { |document| document['_id'] }).to eq %w(a)
      expect(finds.length).to eq 2
      expect(finds[0].last[:projection]).to eq('_id' => 1)
      expect(id_bounds(finds[1].first)).to eq [%w(c a b), %w(a)]
      expect(finds[1].first.to_s).to include('published')
      expect(finds[1].first.to_s).to include('site_id')
    end

    it 'reads the first target without materializing the list' do
      responses << [doc('a'), doc('b'), doc('c')]
      responses << [doc('c')]

      view = query.in_id_order(%w(c a b)).against(collection)

      expect(view.limit(1).first['_id']).to eq 'c'
      expect(id_bounds(finds[1].first).last).to eq %w(c)
    end

    it 'puts an arbitrary store order back into the window sequence' do
      responses << [doc('a'), doc('b'), doc('c')]
      responses << [doc('b'), doc('a')]

      view = query.in_id_order(%w(a b c)).limit(2).against(collection)

      expect(view.map { |document| document['_id'] }).to eq %w(a b)
    end

    def matching(count)
      allow(collection).to receive(:count_documents) { |filter| counted << filter; count }
    end

    it 'counts matching documents without loading them' do
      matching(1)
      view = query.where(published: true).in_id_order(%w(b a)).against(collection)

      expect(view.count_documents).to eq 1
      expect(finds).to be_empty
      expect(id_bounds(counted.first)).to eq [%w(b a)]
      expect(counted.first.to_s).to include('published')
    end

    it 'fills the window from the next candidates when a document vanishes' do
      responses << [doc('a'), doc('b'), doc('c')]
      responses << [doc('b')]
      responses << [doc('c')]

      view = query.in_id_order(%w(a b c)).limit(2).against(collection)

      expect(view.map { |document| document['_id'] }).to eq %w(b c)
      expect(finds.length).to eq 3
    end

    it 'narrows an existing window instead of replacing it' do
      view = query.in_id_order(%w(a b)).limit(0).against(collection)

      expect(view.limit(1).first).to eq nil
      expect(finds).to be_empty
    end

    it 'counts inside the window' do
      matching(4)
      view = query.in_id_order(%w(a b c d)).offset(1).limit(2).against(collection)

      expect(view.count_documents).to eq 2
      expect(finds).to be_empty
    end

    it 'counts nothing past the end of the list' do
      matching(4)
      view = query.in_id_order(%w(a b c d)).offset(5).against(collection)

      expect(view.count_documents).to eq 0
    end

    it 'counts nothing through an empty window without asking the store' do
      view = query.in_id_order(%w(a b)).limit(0).against(collection)

      expect(view.count_documents).to eq 0
      expect(counted).to be_empty
    end

    it 'refuses anything but a list' do
      expect { query.in_id_order('a') }
        .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
    end

    it 'reads a Symbol through the shared scalar grammar' do
      responses << [doc('a'), doc('b')]

      view = query.in_id_order([:b, :a]).against(collection)

      expect(view.map { |document| document['_id'] }).to eq %w(b a)
      expect(id_bounds(finds[0].first)).to eq [%w(b a)]
    end

    it 'answers an empty list without touching the store' do
      view = query.in_id_order([]).against(collection)

      expect(view.to_a).to eq []
      expect(view.count_documents).to eq 0
      expect(finds).to be_empty
      expect(counted).to be_empty
    end

    it 'refuses to combine with order_by, in either direction' do
      expect { query.order_by(:name).in_id_order(%w(a)) }
        .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
      expect { query.in_id_order(%w(a)).order_by(:name) }
        .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
    end

    it 'returns what is left when every candidate vanishes' do
      responses << [doc('a')]
      responses << []

      view = query.in_id_order(%w(a)).limit(1).against(collection)

      expect(view.to_a).to eq []
    end

  end

  describe '#k' do

    subject { query.k(:title, :in) }

    it { is_expected.to eq 'title.in' }

    it 'rejects unknown operators and dotted field names' do
      expect { query.k(:title, :bogus) }.to raise_error(Locomotive::Steam::Adapters::Query::UnsupportedOperator)
      expect { query.k('address.city', :in) }.to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
    end

  end

end
