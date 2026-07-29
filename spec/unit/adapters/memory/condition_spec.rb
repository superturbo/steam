require 'spec_helper'

require_relative '../../../../lib/locomotive/steam/adapters/memory/condition.rb'

describe Locomotive::Steam::Adapters::Memory::Condition do

  let(:locale)    { :en }
  let(:field)     { :title }
  let(:operator)  { :eq }
  let(:name)      { "#{field}.#{operator}" }
  let(:value)     { 'Awesome Site' }
  let(:invalid)     { Locomotive::Steam::Adapters::Query::InvalidValue }
  let(:unsupported) { Locomotive::Steam::Adapters::Query::UnsupportedOperator }

  subject { described_class.new(name, value, locale) }

  def i18n(translations)
    Locomotive::Steam::Models::I18nField.new(:field, translations)
  end

  describe '#matches? localization and presence' do
    let(:entry) { instance_double('Site', title: i18n(en: 'Awesome Site', fr: 'Génial'), content: 'foo') }

    it 'matches a localized field in the current locale' do
      expect(described_class.new('title.eq', 'Awesome Site', :en).matches?(entry)).to eq true
    end

    it 'matches a regular field' do
      expect(described_class.new('content.eq', 'foo', :en).matches?(entry)).to eq true
    end

    it 'treats a localized field missing the current locale as absent' do
      only_fr = instance_double('Site', title: i18n(fr: 'Bonjour'))
      expect(described_class.new(:title, nil, :en).matches?(only_fr)).to eq true
      expect(described_class.new('title.ne', 'x', :en).matches?(only_fr)).to eq true
    end
  end

  describe '#matches? equality and lists' do
    let(:with_tags)    { instance_double('Product', tags: %w(red green)) }
    let(:blank_tags)   { instance_double('Product', tags: nil) }
    let(:without_tags) { instance_double('Product') }
    let(:grunge_band)  { instance_double('Band', kind: 'grunge') }

    def match?(name, value, entry)
      described_class.new(name, value, :en).matches?(entry)
    end

    context 'eq' do
      it('matches a single-level array exactly') { expect(match?(:tags, %w(red green), with_tags)).to eq true }
      it('rejects a non-exact array') { expect(match?(:tags, %w(red), with_tags)).to eq false }
      it('matches a scalar against an element') { expect(match?(:tags, 'red', with_tags)).to eq true }
      it('nil matches a missing field') { expect(match?(:tags, nil, without_tags)).to eq true }
      it('nil matches a present null field') { expect(match?(:tags, nil, blank_tags)).to eq true }
      it('nil does not match a present value') { expect(match?(:tags, nil, with_tags)).to eq false }
    end

    context 'ne' do
      it('matches a present non-null value') { expect(match?('tags.ne', nil, with_tags)).to eq true }
      it('does not match a missing field') { expect(match?('tags.ne', nil, without_tags)).to eq false }
      it('does not match a present null') { expect(match?('tags.ne', nil, blank_tags)).to eq false }
      it('a non-null value matches a present null') { expect(match?('tags.ne', 'red', blank_tags)).to eq true }
      it('a non-null value matches a missing field') { expect(match?('tags.ne', 'red', without_tags)).to eq true }
    end

    context 'in' do
      it('an element is in the list') { expect(match?('tags.in', %w(red), with_tags)).to eq true }
      it('no element is in the list') { expect(match?('tags.in', %w(black), with_tags)).to eq false }
      it('an empty list matches nothing') { expect(match?('tags.in', [], with_tags)).to eq false }
      it('[nil] matches a missing field') { expect(match?('tags.in', [nil], without_tags)).to eq true }
    end

    context 'nin' do
      it('a value in the list is excluded') { expect(match?('tags.nin', %w(red), with_tags)).to eq false }
      it('a missing field always matches') { expect(match?('tags.nin', %w(red), without_tags)).to eq true }
      it('an empty list matches everything') { expect(match?('tags.nin', [], with_tags)).to eq true }
    end

    context 'all' do
      it('the entry contains every value') { expect(match?('tags.all', %w(red green), with_tags)).to eq true }
      it('a missing value fails') { expect(match?('tags.all', %w(red black), with_tags)).to eq false }
      it('an empty list matches nothing') { expect(match?('tags.all', [], with_tags)).to eq false }
      it('a missing field fails') { expect(match?('tags.all', %w(red), without_tags)).to eq false }
      it('a scalar matches a single-value list') { expect(match?('kind.all', %w(grunge), grunge_band)).to eq true }
    end

    context '[nil] against a present null and a locale-missing field' do
      let(:present_null)     { instance_double('Product', tags: nil) }
      let(:locale_missing)   { instance_double('Product', tags: i18n(fr: %w(x))) }

      it('in [nil] matches a present null') { expect(match?('tags.in', [nil], present_null)).to eq true }
      it('nin [nil] excludes a present null') { expect(match?('tags.nin', [nil], present_null)).to eq false }
      it('in [nil] matches locale-missing') { expect(match?('tags.in', [nil], locale_missing)).to eq true }
      it('nin [nil] matches locale-missing') { expect(match?('tags.nin', [nil], locale_missing)).to eq true }
    end
  end

  describe '#matches? exists' do
    let(:present) { instance_double('Product', tags: %w(red)) }
    let(:null)    { instance_double('Product', tags: nil) }
    let(:absent)  { instance_double('Product') }

    def exists?(value, entry)
      described_class.new('tags.exists', value, :en).matches?(entry)
    end

    it('true matches a present field') { expect(exists?(true, present)).to eq true }
    it('true matches a present null') { expect(exists?(true, null)).to eq true }
    it('true excludes a missing field') { expect(exists?(true, absent)).to eq false }
    it('false matches a missing field') { expect(exists?(false, absent)).to eq true }
    it('false excludes a present field') { expect(exists?(false, present)).to eq false }
    it('accepts the string form') { expect(exists?('true', present)).to eq true }
    it('rejects a non-boolean') { expect { exists?('yes', present) }.to raise_error(invalid) }

    it 'treats a localized null translation as present' do
      expect(exists?(true, instance_double('Product', tags: i18n(en: nil)))).to eq true
    end

    it 'treats a field missing the current locale as absent' do
      expect(exists?(true, instance_double('Product', tags: i18n(fr: 'x')))).to eq false
    end
  end

  describe '#matches? size (arrays only)' do
    def size?(value, tags)
      described_class.new('tags.size', value, :en).matches?(instance_double('Product', tags: tags))
    end

    it('matches an array of the right size') { expect(size?(2, %w(a b))).to eq true }
    it('rejects a wrong size') { expect(size?(3, %w(a b))).to eq false }
    it('does not match a string') { expect(size?(3, 'abc')).to eq false }
    it('coerces a string size') { expect(size?('2', %w(a b))).to eq true }
    it('rejects a fractional size') { expect { size?(2.5, %w(a b)) }.to raise_error(invalid) }

    it 'does not match a missing field' do
      expect(described_class.new('tags.size', 1, :en).matches?(instance_double('Product'))).to eq false
    end
  end

  describe '#matches? a plain-field Range' do
    def in_range?(range, price)
      described_class.new(:price, range, :en).matches?(instance_double('Product', price: price))
    end

    it('matches a value inside the range') { expect(in_range?(1..3, 2)).to eq true }
    it('excludes a value outside the range') { expect(in_range?(1..3, 5)).to eq false }
    it('honours an exclusive end') { expect(in_range?(1...3, 3)).to eq false }

    it 'does not match a missing field' do
      expect(described_class.new(:price, 1..3, :en).matches?(instance_double('Product'))).to eq false
    end

    it 'rejects an unbounded range' do
      expect { described_class.new(:price, Range.new(nil, nil), :en) }.to raise_error(invalid)
    end
  end

  describe 'list value normalization and errors' do
    it 'normalizes a scalar nil in a list to [nil]' do
      absent  = instance_double('Product')
      present = instance_double('Product', tags: %w(red))
      expect(described_class.new('tags.in', nil, :en).matches?(absent)).to eq true
      expect(described_class.new('tags.in', nil, :en).matches?(present)).to eq false
    end

    it 'rejects a Range in a list operator' do
      expect { described_class.new('tags.in', 1..3, :en) }.to raise_error(invalid)
    end

    it 'rejects a Regexp given to an explicit list operator' do
      expect { described_class.new('tags.in', /red/, :en) }.to raise_error(invalid)
    end

    it 'treats a plain-field Regexp as a search, not a list operator' do
      cond = described_class.new(:name, /red/, :en)
      expect(cond.matches?(instance_double('Product', name: 'bordeaux red'))).to eq true
      expect(cond.matches?(instance_double('Product', name: 'green'))).to eq false
    end

    it 'does not swallow a field reader error' do
      entry = instance_double('Product')
      allow(entry).to receive(:tags).and_raise('boom')
      expect { described_class.new(:tags, 'x', :en).matches?(entry) }.to raise_error('boom')
    end
  end

  describe '#inspect' do
    let(:name)  { 'price.gt' }
    let(:value) { 42 }
    it('renders field, operator and value') { expect(subject.inspect).to eq('price.gt 42') }
  end

  describe 'decoding the field and operator' do
    context 'with a normal value' do
      it('extracts the field') { expect(subject.field).to eq field }
      it('extracts the operator') { expect(subject.operator).to eq operator }
      it('preserves the value') { expect(subject.value).to eq(value) }
    end

    context 'with a regex value on a plain field' do
      let(:name)  { 'title' }
      let(:value) { /^[a-z]$/ }
      it('the operator becomes matches') { expect(subject.operator).to eq(:matches) }
    end

    context 'with an unsupported operator' do
      let(:name) { 'domains.unsupported' }
      it('raises the shared error') { expect { subject }.to raise_error(unsupported) }
    end

    context 'with a removed Memory-only operator' do
      %w(neq matches).each do |legacy|
        it "raises the shared error for #{legacy}" do
          expect { described_class.new("title.#{legacy}", 'x', locale) }.to raise_error(unsupported)
        end
      end
    end

    context 'with a nested path' do
      let(:name) { 'address.location.ne' }
      it('raises') { expect { subject }.to raise_error(invalid) }
    end
  end
end
