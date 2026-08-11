require 'spec_helper'

require 'set'
require_relative '../../../../lib/locomotive/steam/adapters/query'

describe Locomotive::Steam::Adapters::Query::Criteria do

  let(:unsupported) { Locomotive::Steam::Adapters::Query::UnsupportedOperator }

  def check(criteria)
    described_class.reject_raw_operators!(criteria)
  end

  it 'accepts criteria without a Mongo operator' do
    expect { check('title' => 'Hi', 'price.gt' => 5) }.not_to raise_error
  end

  it 'rejects a raw operator in a key' do
    ['$where', '$or', '$expr', 'field.$gt'].each do |key|
      expect { check(key => 1) }.to raise_error(unsupported)
    end
  end

  it 'rejects a raw operator spelled in another encoding' do
    expect { described_class.reject_raw_operators!('payload' => { '$gt'.encode(Encoding::UTF_16BE) => 1 }) }
      .to raise_error(Locomotive::Steam::Adapters::Query::UnsupportedOperator)
  end

  it 'rejects a raw operator nested in a value' do
    [
      { 'price' => { '$gt' => 5 } },
      { 'price' => [{ '$gt' => 5 }] },
      { 'price' => Set[{ '$gt' => 5 }] },
      { 'price' => { 'a' => [{ 'b' => { '$ne' => 1 } }] } }
    ].each do |criteria|
      expect { check(criteria) }.to raise_error(unsupported)
    end
  end

  it 'accepts a $-prefixed string value — only keys are operators' do
    expect { check('price' => '$100') }.not_to raise_error
    expect { check('tags' => ['$100', '$200']) }.not_to raise_error
  end

  it 'accepts a plain embedded document' do
    expect { check('address' => { 'city' => 'x' }) }.not_to raise_error
  end

  describe '.normalize' do

    it 'stringifies keys' do
      expect(described_class.normalize(name: 'a', 'score' => 1)).to eq('name' => 'a', 'score' => 1)
      expect(described_class.normalize(nil)).to eq({})
    end

    it 'rejects duplicate keys at any depth' do
      [{ :name => 'a', 'name' => 'b' },
       { 'payload' => { :a => 1, 'a' => 2 } },
       { 'payload' => [{ :a => 1, 'a' => 2 }] }].each do |criteria|
        expect { described_class.normalize(criteria) }
          .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
      end
    end

    it 'rejects a key that spells an existing key in another encoding' do
      [{ 'score' => '1', 'score'.encode(Encoding::UTF_16LE) => '2' },
       { 'payload' => { 'name' => 1, 'name'.encode(Encoding::UTF_16LE) => 2 } }].each do |criteria|
        expect { described_class.normalize(criteria) }
          .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue, /duplicate query key/)
      end
    end

    it 'rejects a non-Hash criteria value' do
      ['name', 42, [1, 2]].each do |criteria|
        expect { described_class.normalize(criteria) }
          .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
      end
    end

  end

end
