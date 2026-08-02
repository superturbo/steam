require 'spec_helper'

require 'set'
require_relative '../../../../lib/locomotive/steam/adapters/query'

describe Locomotive::Steam::Adapters::Query::Values do

  let(:invalid) { Locomotive::Steam::Adapters::Query::InvalidValue }

  describe '.boolean' do

    it { expect(described_class.boolean(true)).to eq true }
    it { expect(described_class.boolean(false)).to eq false }
    it { expect(described_class.boolean('true')).to eq true }
    it { expect(described_class.boolean('TRUE')).to eq true }
    it { expect(described_class.boolean('false')).to eq false }
    it { expect(described_class.boolean('False')).to eq false }

    it 'rejects unsupported boolean strings' do
      %w(yes y t 1 1.0 company).each do |value|
        expect { described_class.boolean(value) }.to raise_error(invalid)
      end
    end

    it { expect { described_class.boolean(1) }.to raise_error(invalid) }
    it { expect { described_class.boolean(nil) }.to raise_error(invalid) }

  end

  describe '.size' do

    it { expect(described_class.size(2)).to eq 2 }
    it { expect(described_class.size(0)).to eq 0 }
    it { expect(described_class.size('2')).to eq 2 }
    it { expect(described_class.size('07')).to eq 7 }

    it { expect { described_class.size(-1) }.to raise_error(invalid) }
    it { expect { described_class.size(2.5) }.to raise_error(invalid) }
    it { expect { described_class.size('2.5') }.to raise_error(invalid) }
    it { expect { described_class.size('two') }.to raise_error(invalid) }
    it { expect { described_class.size(nil) }.to raise_error(invalid) }

  end

  describe '.range' do

    it { expect(described_class.range(1..3)).to eq(1..3) }
    it { expect(described_class.range(1..)).to eq(1..) }
    it { expect(described_class.range(..3)).to eq(..3) }

    it { expect { described_class.range(Range.new(nil, nil)) }.to raise_error(invalid) }

  end

  describe '.list' do

    it { expect(described_class.list([1, 2])).to eq [1, 2] }
    it { expect(described_class.list(5)).to eq [5] }
    it { expect(described_class.list(nil)).to eq [nil] }
    it { expect(described_class.list(['a', 1, nil, :sym])).to eq ['a', 1, nil, 'sym'] }
    it { expect(described_class.list(Set.new([1, 2]))).to match_array [1, 2] }

    it 'does not alias the caller array' do
      source = [1, 2]
      expect(described_class.list(source)).not_to be(source)
    end

    it 'rejects a Range rather than enumerating it into a huge query' do
      expect { described_class.list(1..3) }.to raise_error(invalid)
    end

    it 'accepts a plain Hash element — MongoDB compares embedded documents' do
      expect(described_class.list([{ 'city' => 'x' }])).to eq [{ 'city' => 'x' }]
      expect(described_class.list(city: 'x')).to eq [{ 'city' => 'x' }]
    end

    it 'accepts nested arrays — $all defines their semantics' do
      expect(described_class.list([[1, 2], 3])).to eq [[1, 2], 3]
    end

    it 'normalizes a nested Set element to an Array' do
      expect(described_class.list([Set.new([1, 2])])).to eq [[1, 2]]
    end

    it 'rejects a Regexp or Range element — those are plain-field expressions' do
      [[/pattern/], [1..3]].each do |value|
        expect { described_class.list(value) }.to raise_error(invalid)
      end
    end

  end

  describe '.literal' do

    it 'passes scalars and nil through' do
      [5, 'a', nil, 4.2].each { |v| expect(described_class.literal(v)).to eq v }
    end

    it 'reads a Symbol as the string naming it' do
      expect(described_class.literal(:sym)).to eq 'sym'
    end

    it 'normalizes a Set to an Array, recursively' do
      expect(described_class.literal(Set.new([1, 2]))).to eq [1, 2]
      expect(described_class.literal([Set.new([1, 2])])).to eq [[1, 2]]
      expect(described_class.literal('a' => Set.new([1]))).to eq('a' => [1])
    end

    it 'accepts nested arrays' do
      expect(described_class.literal([[1, 2], 3])).to eq [[1, 2], 3]
    end

    it 'accepts a plain Hash and stringifies its keys' do
      expect(described_class.literal(city: 'x', n: 1)).to eq('city' => 'x', 'n' => 1)
      expect(described_class.literal(a: { b: 1 })).to eq('a' => { 'b' => 1 })
    end

    it 'preserves the key order of a Hash — MongoDB embedded equality is ordered' do
      expect(described_class.literal(b: 2, a: 1).keys).to eq %w(b a)
    end

    it 'rejects a key collision created by stringification' do
      expect { described_class.literal(:x => 1, 'x' => 2) }.to raise_error(invalid)
    end

    it 'rejects a Regexp or Range — those are plain-field expressions' do
      expect { described_class.literal(/pattern/) }.to raise_error(invalid)
      expect { described_class.literal(1..3) }.to raise_error(invalid)
    end

    it 'never mutates or aliases the input, however nested' do
      source = { a: [1, Set.new([2])], b: { c: 3 } }
      before = Marshal.dump(source)

      result = described_class.literal(source)

      expect(Marshal.dump(source)).to eq before
      expect(result).not_to be(source)
      expect(result['a']).not_to be(source[:a])
      expect(result['b']).not_to be(source[:b])
    end

  end

  describe '.scalar' do

    it 'passes comparable values through unchanged' do
      [5, 4.2, 'a', Time.now, Date.today, BigDecimal('1.5')].each do |value|
        expect(described_class.scalar(value)).to eq value
      end
    end

    it 'reads a Symbol as the string naming it' do
      expect(described_class.scalar(:sym)).to eq 'sym'
    end

    it 'passes a comparable value the query layer does not know about' do
      id = BSON::ObjectId.new
      expect(described_class.scalar(id)).to eq id
    end

    it 'turns nil into the match-none sentinel' do
      expect(described_class.match_none?(described_class.scalar(nil))).to eq true
    end

    it 'rejects structures — their ordering is not the same on both engines' do
      [[1], { 'a' => 1 }, Set[1], (1..3), /x/].each do |value|
        expect { described_class.scalar(value) }.to raise_error(invalid)
      end
    end

    it 'orders booleans, which both engines sort false before true' do
      [true, false].each { |value| expect(described_class.scalar(value)).to eq value }
    end

  end

  describe '.match_none?' do

    it { expect(described_class.match_none?(described_class.scalar(nil))).to eq true }
    it { expect(described_class.match_none?(nil)).to eq false }
    it { expect(described_class.match_none?(5)).to eq false }

  end

  describe '.coerce' do

    it 'dispatches to the value kind' do
      expect(described_class.coerce(:literal, Set.new([1]))).to eq [1]
      expect(described_class.coerce(:list, 5)).to eq [5]
      expect(described_class.coerce(:boolean, 'true')).to eq true
      expect(described_class.coerce(:size, '2')).to eq 2
      expect(described_class.coerce(:range, 1..3)).to eq(1..3)
    end

    it 'rejects an unknown value kind' do
      expect { described_class.coerce(:bogus, 1) }.to raise_error(invalid)
    end

  end

end
