require 'spec_helper'

describe Locomotive::Steam::ContentEntryService do

  let(:site)              { instance_double('Site', default_locale: 'en') }
  let(:locale)            { 'en' }
  let(:type_repository)   { instance_double('ContentTypeRepository') }
  let(:entry_repository)  { instance_double('Repository', site: site, locale: locale, content_type_repository: type_repository) }
  let(:service)           { described_class.new(type_repository, entry_repository, locale) }

  before { allow(entry_repository).to receive(:with).and_return(entry_repository) }

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
