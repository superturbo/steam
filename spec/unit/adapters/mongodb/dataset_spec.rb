require 'spec_helper'

require_relative '../../../../lib/locomotive/steam/adapters/mongodb/dataset.rb'

describe Locomotive::Steam::Adapters::MongoDB::Dataset do

  let(:documents) { [{ '_id' => 1 }, { '_id' => 2 }] }
  let(:view)      { instance_double('Mongo::Collection::View') }
  let(:limited)   { instance_double('Mongo::Collection::View') }
  let(:mapper)    { instance_double('Mapper') }
  let(:dataset)   { described_class.new(view, mapper) }

  before do
    allow(mapper).to receive(:to_entity) { |attributes| "entity:#{attributes['_id']}" if attributes }
    allow(view).to receive(:map) { |&block| documents.map(&block) }
  end

  def stub_limit_one(document)
    allow(view).to receive(:limit).with(1).and_return(limited)
    allow(limited).to receive(:first).and_return(document)
  end

  describe 'laziness' do
    it 'does not query the view on construction' do
      allow(view).to receive(:each)
      allow(view).to receive(:limit)
      allow(view).to receive(:count_documents)

      described_class.new(view, mapper)

      expect(view).not_to have_received(:each)
      expect(view).not_to have_received(:map)
      expect(view).not_to have_received(:limit)
      expect(view).not_to have_received(:count_documents)
    end
  end

  describe '#each' do
    it 'returns an Enumerator without a block' do
      expect(dataset.each).to be_a(Enumerator)
    end

    it 'streams mapped entities and returns self' do
      allow(view).to receive(:each).and_yield({ '_id' => 1 }).and_yield({ '_id' => 2 })

      yielded = []
      result  = dataset.each { |entity| yielded << entity }

      expect(yielded).to eq ['entity:1', 'entity:2']
      expect(result).to be(dataset)
    end
  end

  describe '#first' do
    it 'fetches a single document via limit(1)' do
      stub_limit_one({ '_id' => 1 })
      expect(dataset.first).to eq 'entity:1'
    end

    it 'returns nil without mapping when nothing is found' do
      stub_limit_one(nil)
      expect(dataset.first).to be_nil
      expect(mapper).not_to have_received(:to_entity)
    end

    it 'materializes and keeps Array semantics for first(n)' do
      expect(dataset.first(1)).to eq ['entity:1']
    end
  end

  describe '#count / #size / #length' do
    before { allow(view).to receive(:count_documents).and_return(2) }

    it { expect(dataset.count).to eq 2 }
    it { expect(dataset.size).to eq 2 }
    it { expect(dataset.length).to eq 2 }

    it 'materializes for count(value)' do
      expect(dataset.count('entity:1')).to eq 1
    end

    it 'materializes for count { block }' do
      expect(dataset.count { |e| e == 'entity:2' }).to eq 1
    end
  end

  describe '#empty?' do
    it 'is true when no document is found, without mapping' do
      stub_limit_one(nil)
      expect(dataset.empty?).to be true
      expect(mapper).not_to have_received(:to_entity)
    end

    it 'is false when a document exists' do
      stub_limit_one({ '_id' => 1 })
      expect(dataset.empty?).to be false
    end
  end

  describe '#all and delegation' do
    it 'materializes once and reuses the same array' do
      first_call  = dataset.all
      second_call = dataset.all

      expect(first_call).to eq ['entity:1', 'entity:2']
      expect(second_call).to be(first_call)
      expect(view).to have_received(:map).once
    end

    it 'delegates #last and #map to the materialized array' do
      expect(dataset.last).to eq 'entity:2'
      expect(dataset.map { |e| e.upcase }).to eq ['ENTITY:1', 'ENTITY:2']
    end
  end

  describe 'fast paths do not materialize' do
    it '#first, #each and #count never call view.map' do
      stub_limit_one({ '_id' => 1 })
      allow(view).to receive(:each)
      allow(view).to receive(:count_documents).and_return(0)

      dataset.first
      dataset.each { |_| }
      dataset.count

      expect(view).not_to have_received(:map)
    end
  end

  describe 'snapshot semantics after materialization' do
    it 'reuses @records and never re-queries the view' do
      allow(view).to receive(:limit).and_return(limited)
      allow(limited).to receive(:first)
      allow(view).to receive(:count_documents)
      allow(view).to receive(:each)

      dataset.all # materialize

      expect(dataset.first).to eq 'entity:1'
      expect(dataset.count).to eq 2
      expect(dataset.size).to eq 2
      expect(dataset.empty?).to be false
      dataset.each { |_| }

      expect(view).not_to have_received(:limit)
      expect(view).not_to have_received(:count_documents)
      expect(view).not_to have_received(:each)
    end
  end

end
