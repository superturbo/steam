require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/memory.rb'
require_relative '../../support/examples/adapter_contract'

describe Locomotive::Steam::MemoryAdapter do

  let(:collection)  { [OpenStruct.new(name: 'Hello world')] }
  let(:mapper)      { instance_double('Mapper', name: :test) }
  let(:scope)       { instance_double('Scope', locale: nil) }
  let(:adapter)     { Locomotive::Steam::MemoryAdapter.new(collection) }

  before { allow(mapper).to receive(:to_entity) { |arg| arg } }

  it_behaves_like 'a repository adapter'

  describe 'read-only writes' do
    it 'returns the id unchanged from make_id' do
      expect(adapter.make_id('an-id')).to eq 'an-id'
    end

    {
      create: [nil, nil, nil],
      update: [nil, nil, nil],
      inc:    [nil, nil, nil, :views, 1],
      delete: [nil, nil, nil]
    }.each do |write, args|
      it "raises UnsupportedWrite from ##{write}" do
        expect { adapter.public_send(write, *args) }.to raise_error(described_class::UnsupportedWrite)
      end
    end
  end

  describe '#all' do

    subject { adapter.all(mapper, scope) }
    it { expect(subject.size).to eq 1 }

  end

  describe '#query' do

    let(:block) { -> (_) { where(name: 'Hello world') } }
    subject { adapter.query(mapper, scope, &block) }
    it { expect(subject.size).to eq 1 }

    context 'another syntax' do

      let(:block) { -> (_) { where(k(:name, :in) => ['Hello world']) } }
      it { expect(subject.size).to eq 1 }

    end

  end

  describe '#count' do

    let(:collection) { [OpenStruct.new(name: 'a'), OpenStruct.new(name: 'b')] }

    it 'counts every record' do
      expect(adapter.count(mapper, scope)).to eq 2
    end

    it 'counts the records matching the block filter' do
      expect(adapter.count(mapper, scope) { where(name: 'a') }).to eq 1
    end

  end

end
