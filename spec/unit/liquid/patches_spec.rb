require 'spec_helper'

describe ::Liquid::Condition do

  let(:context)   { Liquid::Context.new }
  let(:condition) { described_class.new(left, op, right) }

  subject { condition.evaluate(context) }

  describe 'custom proc operator: starts_with' do

    let(:op)    { 'starts_with' }
    let(:left)  { 'Hello world' }
    let(:right) { 'Hello' }

    it { is_expected.to eq true }

    context "the left variable doesn't start with the right variable" do
      let(:right) { 'hello' }
      it { is_expected.to eq false }
    end

    context 'the left variable is nil' do
      let(:left) { nil }
      it { is_expected.to eq false }
    end

    context 'the right variable is nil' do
      let(:right) { nil }
      it { is_expected.to eq false }
    end

  end

  describe 'custom proc operator: is' do

    let(:op)    { 'is' }
    let(:left)  { 42 }
    let(:right) { 42 }

    it { is_expected.to eq true }

    context "the left variable doesn't equal to the right variable" do
      let(:right) { nil }
      it { is_expected.to eq false }
    end

  end

end

describe 'Rendering with the Liquid patches' do

  let(:assigns) { {} }
  let(:context) { ::Liquid::Context.new(assigns, {}, {}) }

  subject { render_template(source, context) }

  describe 'the "is present" condition' do

    let(:source) { "{% if title is present %}present{% else %}blank{% endif %}" }

    context 'with a value' do
      let(:assigns) { { 'title' => 'Hello' } }
      it { is_expected.to eq 'present' }
    end

    context 'with a blank string' do
      let(:assigns) { { 'title' => '' } }
      it { is_expected.to eq 'blank' }
    end

    context 'with no value' do
      it { is_expected.to eq 'blank' }
    end

  end

  describe 'the "starts_with" condition' do

    let(:source) { "{% if title starts_with 'Hello' %}yes{% else %}no{% endif %}" }

    context 'the value starts with the string' do
      let(:assigns) { { 'title' => 'Hello world' } }
      it { is_expected.to eq 'yes' }
    end

    context 'the value does not start with the string' do
      let(:assigns) { { 'title' => 'Goodbye world' } }
      it { is_expected.to eq 'no' }
    end

  end

  describe 'Date/Time values passed to numeric filters' do

    # numeric filters go through Liquid::Utils.to_number which knows nothing
    # about dates (returns 0), no matter what the to_number patch suggests.
    let(:assigns) { { 'today' => Date.parse('2007-06-29'), 'now' => Time.utc(2007, 6, 29) } }
    let(:source)  { "{{ today | plus: 1 }}/{{ now | plus: 1 }}" }

    it { is_expected.to eq '1/1' }

  end

end

describe ::Liquid::StandardFilters do

  describe '#to_number' do

    subject { SimpleFilters.new.send(:to_number, obj) }

    context 'Integer' do
      let(:obj) { 42 }
      it { is_expected.to eq 42 }
    end

    context 'String (Integer)' do
      let(:obj) { '42' }
      it { is_expected.to eq 42 }
    end

    context 'String (Float)' do
      let(:obj) { '42.00' }
      it { is_expected.to eq 42.0 }
    end

    context 'Date' do
      let(:obj) { Date.parse('2007/06/29') }
      it { is_expected.to be >= 1183068000 }
    end

    context 'Time' do
      let(:obj) { Time.parse('2007/06/29 00:00:00') }
      it { is_expected.to be >= 1183068000 }
    end

    context 'DateTime' do
      let(:obj) { DateTime.parse('2007/06/29 00:00:00+0000') }
      it { is_expected.to eq 1183075200 }
    end

    context 'Other object' do
      let(:obj) { nil }
      it { is_expected.to eq 0 }
    end

  end

  class SimpleFilters
    include Liquid::StandardFilters
  end

end
