require 'spec_helper'

describe Locomotive::Steam::ContentTypeField do

  let(:attributes)    { { name: 'title', type: 'string' } }
  let(:field)         { described_class.new(attributes) }

  describe '#type' do

    subject { field.type }
    it { is_expected.to eq :string }

  end

  describe '#order_by' do

    subject { field.order_by }
    it { is_expected.to eq nil }

    context 'has_many field' do

      let(:attributes) { { name: 'articles', type: 'has_many', inverse_of: 'author' } }
      it { is_expected.to eq(position_in_author: 'asc') }

      context 'order_by is specified' do

        let(:attributes) { { name: 'articles', type: 'has_many', inverse_of: 'author', order_by: 'name asc' } }
        it { is_expected.to eq(name: 'asc') }

      end

    end

  end

  describe '#target_id' do

    subject { field.target_id }
    it { is_expected.to eq nil }

    context 'slug' do

      let(:attributes) { { name: 'articles', class_name: 'articles' } }
      it { is_expected.to eq 'articles' }

    end

    context 'class name' do

      let(:attributes) { { name: 'articles', class_name: 'Locomotive::ContentEntry42' } }
      it { is_expected.to eq '42' }

    end

  end

  describe '#association_options' do

    let(:attributes) { { name: 'articles', class_name: 'articles', type: 'has_many', inverse_of: 'author' } }

    subject { field.association_options }

    it { is_expected.to eq(target_id: 'articles', inverse_of: 'author', order_by: { position_in_author: 'asc' }) }

  end

  describe '#is_relationship?' do

    let(:attributes) { { name: 'articles', class_name: 'articles', type: 'has_many', inverse_of: 'author' } }

    subject { field.is_relationship? }

    it { is_expected.to eq true }

  end

  describe 'the capability model' do

    { string:       [true,  true],
      text:         [true,  true],
      email:        [true,  true],
      color:        [true,  true],
      integer:      [true,  true],
      float:        [true,  true],
      date:         [true,  true],
      date_time:    [true,  true],
      boolean:      [true,  true],
      select:       [true,  true],
      file:         [true,  true],
      tags:         [true,  false],
      json:         [true,  true],
      belongs_to:   [false, true],
      many_to_many: [false, true],
      has_many:     [false, true],
      password:     [false, false] }.each do |type, (localizable, required_supported)|

      it "#{type} is supported: localization #{localizable ? 'yes' : 'no'}, " \
         "required #{required_supported ? 'yes' : 'no'}" do
        field = described_class.new(type: type)

        expect(field.supported?).to be true
        expect(field.supports_localization?).to be localizable
        expect(field.supports_required?).to be required_supported
      end

    end

    it 'does not support an unknown type at all' do
      field = described_class.new(type: :money)

      expect(field.supported?).to be false
      expect(field.supports_localization?).to be false
      expect(field.supports_required?).to be false
    end

  end

  describe '#persisted_name' do

    subject { field.persisted_name }

    context 'string type' do

      let(:attributes) { { name: 'title', type: 'string' } }
      it { is_expected.to eq 'title' }

    end

    context 'select type' do

      let(:attributes) { { name: 'category', type: 'select' } }
      it { is_expected.to eq 'category_id' }

    end

    context 'belongs_to type' do

      let(:attributes) { { name: 'article', class_name: 'articles', type: 'belongs_to' } }
      it { is_expected.to eq 'article_id' }

    end

    context 'many_to_many type' do

      let(:attributes) { { name: 'articles', class_name: 'articles', type: 'many_to_many' } }
      it { is_expected.to eq 'article_ids' }

    end

    context 'has_many type' do

      let(:attributes) { { name: 'articles', class_name: 'articles', type: 'has_many', inverse_of: 'author' } }
      it { is_expected.to eq nil }

    end

  end

end
