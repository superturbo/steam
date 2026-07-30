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

end
