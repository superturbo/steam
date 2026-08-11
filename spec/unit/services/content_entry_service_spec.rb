require 'spec_helper'

describe Locomotive::Steam::ContentEntryService do

  let(:site)              { instance_double('Site', default_locale: 'en') }
  let(:locale)            { 'en' }
  let(:type_repository)   { instance_double('ContentTypeRepository') }
  let(:entry_repository)  { instance_double('Repository', site: site, locale: locale, content_type_repository: type_repository) }
  let(:service)           { described_class.new(type_repository, entry_repository, locale) }

  before { allow(entry_repository).to receive(:with).and_return(entry_repository) }

  describe '#update_decorated_entry' do

    let(:title_field)  { instance_double('Field', name: :title, type: :string, is_relationship?: false) }
    let(:fields)       { instance_double('Fields', json: [], selects: []) }
    let(:content_type) do
      instance_double('ContentType', slug: 'articles', fields: fields, label_field_name: :title,
                                     fields_by_name: { title: title_field }.with_indifferent_access,
                                     persisted_field_names: [:title])
    end
    let(:entry) do
      Locomotive::Steam::ContentEntry.new(title: 'Old').tap do |_entry|
        _entry.content_type         = content_type
        _entry.localized_attributes = {}
      end
    end
    let(:decorated) { Locomotive::Steam::Decorators::I18nDecorator.new(entry, locale) }

    before do
      allow(entry_repository).to receive(:content_type).and_return(content_type)
      allow(entry_repository).to receive(:resolve_selects) { |attributes| attributes }
    end

    it 'keeps the decorator attached to the written entity' do
      written = nil
      allow(entry_repository).to receive(:update) { |entity| written = entity }

      result = service.update_decorated_entry(decorated, 'title' => 'New')

      expect(result).to be(decorated)
      expect(result.__getobj__).to be(written)
      expect(result.__getobj__).not_to be(entry)
    end

  end

  describe '#validate' do

    let(:attributes)        { { title: 'Hello world' } }
    let(:unique_fields)     { {} }
    let(:first_validation)  { false }
    let(:errors)            { Locomotive::Steam::Models::Concerns::Validation::Errors.new }
    let(:type)              { instance_double('Comments') }
    let(:entry_id)          { nil }
    let(:entry)             { instance_double('Entry', _id: entry_id, title: 'Hello world', content_type: type, valid?: first_validation, errors: errors, attributes: { title: 'Hello world' }, localized_attributes: []) }

    before do
      allow(type_repository).to receive(:by_slug).and_return(type)
      allow(type_repository).to receive(:look_for_unique_fields).and_return(unique_fields)
      allow(entry_repository).to receive(:build).with(attributes).and_return(entry)
    end

    subject { service.send(:validate, entry_repository, entry) }

    context 'valid' do

      let(:first_validation) { true }

      it { is_expected.to eq true }
      it { subject; expect(entry.errors.empty?).to eq true }

    end

    context 'not valid' do

      before { errors.add(:body, :blank) }

      it { is_expected.to eq false }

      context 'with unique fields' do

        let(:unique_fields) { { title: instance_double('Field', name: 'title') } }

        before do
          allow(entry_repository).to receive(:exists?)
            .with(title: 'Hello world', :'_id.ne' => entry_id).and_return(true)
        end

        context 'the entry has never been persisted before' do

          it { is_expected.to eq false }
          it { subject; expect(entry.errors[:title]).to eq(['must be unique']) }

        end

        context 'the entry has already been persisted' do

          let(:entry_id) { 42 }

          it { is_expected.to eq false }
          it { subject; expect(entry.errors[:title]).to eq(['must be unique']) }

        end

        context 'the field already has an error' do

          before { errors.add(:title, :invalid) }

          it 'does not look for a duplicate of a value the entry rejected' do
            expect(entry_repository).not_to receive(:exists?)
            subject
          end

          it { subject; expect(entry.errors[:title]).to eq(['is invalid']) }

        end

      end

    end

  end

end
