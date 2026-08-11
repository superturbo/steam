require 'spec_helper'

require_relative '../../../../lib/locomotive/steam/adapters/query'

describe Locomotive::Steam::Adapters::Query::Operators do

  let(:unsupported) { Locomotive::Steam::Adapters::Query::UnsupportedOperator }
  let(:invalid)     { Locomotive::Steam::Adapters::Query::InvalidValue }

  describe '.fetch' do

    {
      eq:     [:literal, '$eq'],
      ne:     [:literal, '$ne'],
      gt:     [:scalar,  '$gt'],
      gte:    [:scalar,  '$gte'],
      lt:     [:scalar,  '$lt'],
      lte:    [:scalar,  '$lte'],
      in:     [:list,    '$in'],
      nin:    [:list,    '$nin'],
      all:    [:all_list, '$all'],
      size:   [:size,    '$size'],
      exists: [:boolean, '$exists'],
    }.each do |name, (value_kind, mongo_operator)|
      it "maps #{name} to #{mongo_operator} (#{value_kind})" do
        operator = described_class.fetch(name)
        expect(operator.name).to eq name
        expect(operator.mongo_operator).to eq mongo_operator
        expect(operator.value_kind).to eq value_kind
      end
    end

    it 'normalizes the == alias to eq' do
      expect(described_class.fetch('==').name).to eq :eq
    end

    it 'accepts a string operator' do
      expect(described_class.fetch('gt').name).to eq :gt
    end

    it 'raises on a removed operator' do
      %w(neq matches near within).each do |operator|
        expect { described_class.fetch(operator) }.to raise_error(unsupported)
      end
    end

    it 'raises on an unknown operator' do
      expect { described_class.fetch('approx') }.to raise_error(unsupported)
    end

  end

  describe '.[]' do

    it { expect(described_class['gt'].name).to eq :gt }
    it { expect(described_class['=='].name).to eq :eq }
    it { expect(described_class['neq']).to be_nil }
    it { expect(described_class['approx']).to be_nil }

  end

  describe '.key' do

    it { expect(described_class.key(:views, 'gt')).to eq 'views.gt' }
    it { expect(described_class.key('created_at', :lte)).to eq 'created_at.lte' }
    it { expect(described_class.key(:name, '==')).to eq 'name.eq' }

    it 'raises on a removed or unknown operator' do
      expect { described_class.key(:name, 'neq') }.to raise_error(unsupported)
    end

    it 'never builds a key from an empty or dotted field' do
      expect { described_class.key('', 'gt') }.to raise_error(invalid)
      expect { described_class.key('address.city', 'gt') }.to raise_error(invalid)
    end

  end

  describe '.decode' do

    it 'returns a plain field when there is no operator suffix' do
      expect(described_class.decode('title')).to eq ['title', nil]
    end

    it 'splits a field and its registered operator' do
      field, operator = described_class.decode('views.gt')
      expect(field).to eq 'views'
      expect(operator.name).to eq :gt
    end

    it 'resolves an alias' do
      expect(described_class.decode('name.==').last.name).to eq :eq
    end

    it 'reads a readable field name through its own encoding' do
      expect(described_class.decode('title'.encode(Encoding::UTF_16LE))).to eq ['title', nil]
    end

    it 'rejects a field name in no readable encoding without echoing it' do
      expect { described_class.decode(%(caf\xFF)) }
        .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue,
                        'a field name must be readable text')
    end

    it 'raises on a removed or unknown operator' do
      %w(title.neq title.matches title.bogus).each do |key|
        expect { described_class.decode(key) }.to raise_error(unsupported)
      end
    end

    it 'raises on an empty field' do
      ['', '.ne'].each do |key|
        expect { described_class.decode(key) }.to raise_error(invalid)
      end
    end

    it 'raises on a nested path' do
      expect { described_class.decode('address.location.ne') }.to raise_error(invalid)
    end

  end

  describe 'PUBLIC' do

    it 'is the with_scope surface, without eq or aliases' do
      expect(described_class::PUBLIC).to match_array(%i(all exists gt gte in lt lte ne nin size))
    end

    it 'exposes no operator absent from the registry' do
      described_class::PUBLIC.each do |name|
        expect(described_class.fetch(name).name).to eq name
      end
    end

  end

end
