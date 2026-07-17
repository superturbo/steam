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
    it { expect(described_class.list(['a', 1, nil, :sym])).to eq ['a', 1, nil, :sym] }
    it { expect(described_class.list(Set.new([1, 2]))).to match_array [1, 2] }

    it 'does not alias the caller array' do
      source = [1, 2]
      expect(described_class.list(source)).not_to be(source)
    end

    it 'rejects a Range rather than enumerating it into a huge query' do
      expect { described_class.list(1..3) }.to raise_error(invalid)
    end

    it 'rejects a Hash value' do
      expect { described_class.list(city: 'x') }.to raise_error(invalid)
    end

    it 'rejects non-scalar elements' do
      [[1, [2, 3]], [1, { city: 'x' }], [/pattern/], [1..3], [Set.new([1])]].each do |value|
        expect { described_class.list(value) }.to raise_error(invalid)
      end
    end

  end

end
