require 'spec_helper'

require_relative '../../../../lib/locomotive/steam/adapters/memory/dataset.rb'
require_relative '../../../../lib/locomotive/steam/adapters/memory/condition.rb'
require_relative '../../../../lib/locomotive/steam/adapters/memory/order.rb'
require_relative '../../../../lib/locomotive/steam/adapters/memory/query.rb'

describe Locomotive::Steam::Adapters::Memory::Query do

  let(:entry_1) { OpenStruct.new(name: 'foo', id: 1, attributes: { name: 'foo', id: 1 }) }
  let(:entry_2) { OpenStruct.new(name: 'bar', id: 2, attributes: { name: 'bar', id: 2 }) }
  let(:entry_3) { OpenStruct.new(name: 'zone', id: 3, attributes: { name: 'zone', id: 3 }) }
  let(:records) { { 1 => entry_1, 2 => entry_2, 3 => entry_3 } }
  let(:dataset) { Locomotive::Steam::Adapters::Memory::Dataset.new(:test) }
  let(:locale)  { :en }

  let(:query)   { Locomotive::Steam::Adapters::Memory::Query }

  before { allow(dataset).to receive(:records).and_return(records) }

  describe '#only' do
    specify do
      expect(
        query.new(dataset, locale) do
          only(:name)
        end.all.map(&:name)
      ).to eq(['foo', 'bar', 'zone'])
    end
  end

  describe '#limited' do
    specify do
      expect(
        query.new(dataset, locale) do
          limit(1)
        end.all
      ).to eq([entry_1])
    end
  end

  describe '#offset' do
    specify do
      expect(
        query.new(dataset, locale) do
          offset(1)
        end.all.map(&:name)
      ).to eq(['bar', 'zone'])
    end
  end

  describe '#order_by' do

    context 'asc' do
      specify do
        expect(
          query.new(dataset, locale) do
            order_by('name asc')
          end.all.map(&:name)
        ).to eq(['bar', 'foo', 'zone'])
      end
    end

    context 'desc' do
      specify do
        expect(
          query.new(dataset, locale) do
            order_by('name desc')
          end.all.map(&:name)
        ).to eq(['zone', 'foo', 'bar'])
      end
    end
  end

  describe '#where' do
    specify do
      expect(
        query.new(dataset, locale) do
          where('name.eq' => 'foo').
          where('id.lt' => 2)
        end.all.map(&:name)
      ).to eq(['foo'])
    end
  end

  describe '#+' do
    specify 'mutates and returns the left query, merging in the other conditions' do
      q1 = query.new(dataset, locale) { where('name.eq' => 'foo') }
      q2 = query.new(dataset, locale) { where('id.lt' => 2) }
      merged = q1 + q2

      expect(merged).to be(q1)
      expect(merged.conditions.size).to eq(2)
      expect(merged.all.map(&:name)).to eq(['foo'])
    end
  end

  describe "#where with the 'all' operator" do
    # Locks the public adapter contract ($all) exercised by other LocomotiveCMS
    # gems through the query DSL, not just Condition in isolation.
    let(:entry_1) { OpenStruct.new(name: 'foo', tags: %w(red green blue)) }
    let(:entry_2) { OpenStruct.new(name: 'bar', tags: %w(red)) }
    let(:records) { { 1 => entry_1, 2 => entry_2 } }

    specify 'keeps only entries whose array contains every queried value' do
      result = query.new(dataset, locale) { where('tags.all' => %w(red green)) }.all
      expect(result.map(&:name)).to eq(['foo'])
    end
  end

  describe '#==' do
    context 'compared to an Array' do
      specify 'materializes and compares the results' do
        expect(query.new(dataset, locale)).to eq([entry_1, entry_2, entry_3])
      end
    end

    context 'compared to a non-Array' do
      specify 'falls back to object identity' do
        expect(query.new(dataset, locale) == 'foo').to eq(false)
      end
    end
  end

  describe '.key' do

    subject { query.key(:title, :in) }

    it { is_expected.to eq 'title.in' }

    it 'rejects unknown operators and dotted field names' do
      expect { query.key(:title, :bogus) }.to raise_error(Locomotive::Steam::Adapters::Query::UnsupportedOperator)
      expect { query.key('address.city', :in) }.to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
    end

  end

end
