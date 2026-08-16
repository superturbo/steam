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

  describe '#in_id_order' do

    def names(&block)
      query.new(dataset, locale, &block).all.map(&:name)
    end

    it 'restricts to the given IDs and preserves their order' do
      expect(names { in_id_order([3, 1]) }).to eq(['zone', 'foo'])
    end

    it 'skips a missing ID' do
      expect(names { in_id_order([3, 99, 1]) }).to eq(['zone', 'foo'])
    end

    it 'keeps a duplicate ID at its first position' do
      expect(names { in_id_order([3, 1, 3]) }).to eq(['zone', 'foo'])
    end

    it 'applies the window after the sequence' do
      expect(names { in_id_order([3, 1, 2]).offset(1).limit(1) }).to eq(['foo'])
    end

    it 'still applies the other conditions' do
      expect(names { where(name: 'foo').in_id_order([3, 1]) }).to eq(['foo'])
    end

    it 'refuses anything but a list' do
      expect { query.new(dataset, locale) { in_id_order(3) } }
        .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
    end

    it 'refuses a structural ID inside the list' do
      expect { query.new(dataset, locale) { in_id_order([[3, 1]]) } }
        .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
    end

    it 'answers an empty list without touching the dataset' do
      empty = query.new(dataset, locale) { in_id_order([]) }

      expect(empty.all).to eq []
      expect(empty.count).to eq 0
      expect(dataset).not_to have_received(:records)
    end

    context 'records stored under string identities' do

      let(:records) { { 'zone' => entry_3, 'foo' => entry_1 } }
      let(:entry_1) { OpenStruct.new(name: 'foo', _id: 'foo', attributes: { name: 'foo', _id: 'foo' }) }
      let(:entry_3) { OpenStruct.new(name: 'zone', _id: 'zone', attributes: { name: 'zone', _id: 'zone' }) }

      it 'reads a Symbol through the shared scalar grammar' do
        expect(names { in_id_order([:zone, :foo]) }).to eq(['zone', 'foo'])
      end

    end

    it 'refuses to combine with order_by, in either direction' do
      expect { query.new(dataset, locale) { order_by('name asc').in_id_order([3]) } }
        .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
      expect { query.new(dataset, locale) { in_id_order([3]).order_by('name asc') } }
        .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
    end

    it 'keeps its own copy of the list' do
      ids     = [3, 1]
      ordered = query.new(dataset, locale) { in_id_order(ids) }
      ids.clear

      expect(ordered.all.map(&:name)).to eq(['zone', 'foo'])
    end

    context 'a record with a composite [mongo_id, slug] identity' do

      let(:entry_3) do
        OpenStruct.new(name: 'zone', _id: ['5baf7d38a953300567956448', 'zone'],
                       attributes: { name: 'zone', _id: ['5baf7d38a953300567956448', 'zone'] })
      end
      let(:records) { { '5baf7d38a953300567956448' => entry_3, 2 => entry_2 } }

      it 'takes the position of any identity component' do
        expect(names { in_id_order([2, 'zone']) }).to eq(['bar', 'zone'])
      end

      it 'answers a component once even when both are given' do
        expect(names { in_id_order(['zone', 2, '5baf7d38a953300567956448']) }).to eq(['zone', 'bar'])
      end

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

    context 'equal keys' do

      let(:records) do
        (1..32).to_h do |index|
          group = index.odd? ? 'a' : 'b'
          [index, OpenStruct.new(id: index, group: group, attributes: { id: index, group: group })]
        end
      end

      it 'keeps the dataset order inside each group' do
        expect(
          query.new(dataset, locale) { order_by('group asc') }.all.map(&:id)
        ).to eq((1..32).select(&:odd?) + (1..32).select(&:even?))
      end

      it 'keeps it for the reversed direction too' do
        expect(
          query.new(dataset, locale) { order_by('group desc') }.all.map(&:id)
        ).to eq((1..32).select(&:even?) + (1..32).select(&:odd?))
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

  describe '#where — raw Mongo operators' do

    let(:unsupported) { Locomotive::Steam::Adapters::Query::UnsupportedOperator }

    def where(conditions)
      query.new(dataset, :en).where(conditions)
    end

    it 'rejects a raw operator in a key' do
      expect { where('$where' => 'sleep(1000)') }.to raise_error(unsupported)
    end

    it 'rejects a raw operator nested in a value' do
      expect { where('price' => { '$gt' => 5 }) }.to raise_error(unsupported)
      expect { where('price' => [{ '$gt' => 5 }]) }.to raise_error(unsupported)
    end

    it 'accepts a $-prefixed string value' do
      expect { where('name' => '$100') }.not_to raise_error
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
