require 'spec_helper'

describe Locomotive::Steam::Models::I18nField do

  let(:name)          { 'title' }
  let(:translations)  { nil }
  let(:field)         { described_class.new(name, translations) }

  describe '#blank?' do

    subject { field.blank? }

    it { is_expected.to eq true }

    context 'with translations' do

      let(:translations) { { en: 'Hello world', fr: nil } }

      it { is_expected.to eq false }

    end

    context 'with a single value' do

      let(:translations) { 'Hello world' }

      it { is_expected.to eq false }

    end

  end

  describe '#dup' do

    let(:translations) { { en: 'Hello world', fr: nil } }

    subject { field.dup }

    it 'gets a fresh copy of the translations' do
      expect(subject[:en]).to eq 'Hello world'
      expect(subject.translations.object_id).not_to eq field.translations.object_id
    end

  end

  describe '#to_json' do

    let(:translations) { { en: 'Hello world', fr: nil } }

    subject { field.to_json }

    it { is_expected.to eq("{\"en\":\"Hello world\",\"fr\":null}") }

  end

  describe '#serialize' do

    def serialized(field)
      {}.tap { |attributes| field.serialize(attributes) }[field.name]
    end

    it 'keeps a scalar a scalar, through dup and duplicate' do
      field = described_class.new(:title, 'Plain')

      expect(serialized(field)).to eq 'Plain'
      expect(serialized(field.dup)).to eq 'Plain'
      expect(serialized(field.duplicate(:other))).to eq 'Plain'
    end

    it 'keeps an empty hash an empty hash, through dup too' do
      field = described_class.new(:title, {})

      expect(serialized(field)).to eq({})
      expect(serialized(field.dup)).to eq({})
    end

    it 'becomes a locale hash once a translation is written' do
      field = described_class.new(:title, 'Plain')
      field[:fr] = 'Bonjour'

      expect(serialized(field)).to eq('fr' => 'Bonjour')
    end

  end

end
