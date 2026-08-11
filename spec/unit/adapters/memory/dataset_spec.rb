require 'spec_helper'

require_relative '../../../../lib/locomotive/steam/adapters/memory/dataset.rb'

describe Locomotive::Steam::Adapters::Memory::Dataset do

  let(:john) do
    {
      firstname: 'John',
      lastname: 'Doe',
      email: 'john@example.com',
      age: 24
    }
  end

  let(:jane) do
    {
      firstname: 'Jane',
      lastname: 'Doe',
      email: 'jane@example.com',
      age: 20
    }
  end

  let(:alex) do
    {
      firstname: 'Alex',
      lastname: 'Turam',
      email: 'alex@example.com',
      age: 26
    }
  end

  subject { Locomotive::Steam::Adapters::Memory::Dataset.new(:foo) } #(loader) }

  before do
    [john.to_hash, jane.to_hash, alex.to_hash].each do |record|
      subject.insert record
    end
  end

  describe '#all' do
    it { expect(subject.all).to eq [john.to_hash, jane.to_hash, alex.to_hash] }
  end

  describe '#find' do
    specify do
      expect(subject.find(john[:_id])).to eq(john.to_hash)
    end
  end

  describe '#insert' do
    it 'rejects a record whose identity is already taken' do
      impostor = { _id: john[:_id], firstname: 'Impostor' }

      expect { subject.insert(impostor) }.to raise_error(described_class::InvalidIdentity)
      expect(subject.find(john[:_id])[:firstname]).to eq('John')
    end
  end

  describe '#update' do
    before do
      subject.update(jane.to_hash.merge(lastname: 'birkin'))
    end

    specify do
      expect(subject.find(jane[:_id]).fetch(:lastname)).to eq('birkin')
    end

    it 'raises rather than upserting an unknown record' do
      expect { subject.update(_id: 'nope', name: 'x') }
        .to raise_error(Locomotive::Steam::Models::Repository::RecordNotFound)
    end
  end

  describe '#delete' do
    it 'raises rather than ignoring an unknown record' do
      expect { subject.delete('nope') }
        .to raise_error(Locomotive::Steam::Models::Repository::RecordNotFound)
    end
  end

  describe '#exists?' do
    let(:dataset) { Locomotive::Steam::Adapters::Memory::Dataset.new(:dummy) }
    before do
      dataset.instance_variable_set('@records', { 1 => 'Record 1', 2 => 'Record 2' })
    end

    it { expect(dataset.exists?(2)).to eq true  }
    it { expect(dataset.exists?(3)).to eq false  }
    it { expect(dataset.exists?(nil)).to eq false  }

  end

  describe 'what it keeps' do

    let(:record) { { name: +'Bowie' } }

    it 'is not the record it was handed' do
      subject.insert(record)
      record[:name] << ' Pop'

      expect(subject.find(record[:_id])[:name]).to eq 'Bowie'
    end

    it 'is not the record an update hands it either' do
      subject.insert(record)
      written = { _id: record[:_id], name: +'Iggy' }
      subject.update(written)
      written[:name] << ' Pop'

      expect(subject.find(record[:_id])[:name]).to eq 'Iggy'
    end

    it 'is not what a record holds either' do
      record[:labels] = [+'one']
      subject.insert(record)
      record[:labels] << 'two'
      record[:labels].first << ' more'

      expect(subject.find(record[:_id])[:labels]).to eq ['one']
    end

  end

  describe '#reindex!' do
    let(:invalid) { Locomotive::Steam::Adapters::Memory::Dataset::InvalidIdentity }
    let(:record)  { { name: 'Bowie' } }

    before { subject.insert(record) }

    it 'moves the record to its new identity and drops the old key' do
      old_key = record[:_id]
      subject.find(old_key)[:_id] = 'bowie'
      subject.reindex!

      expect(subject.find('bowie')[:name]).to eq 'Bowie'
      expect(subject.exists?(old_key)).to eq false
    end

    it 'fails fast on a missing identity' do
      subject.find(record[:_id]).delete(:_id)
      expect { subject.reindex! }.to raise_error(invalid, /without an _id/)
    end

    it 'fails fast on a duplicate identity' do
      other = { name: 'Iggy' }
      subject.insert(other)
      subject.find(record[:_id])[:_id] = 'clash'
      subject.find(other[:_id])[:_id] = 'clash'

      expect { subject.reindex! }.to raise_error(invalid, /duplicate/)
    end
  end
end
