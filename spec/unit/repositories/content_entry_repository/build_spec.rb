require 'spec_helper'

require_relative '../../../support/content_entry_repository_context'

describe Locomotive::Steam::ContentEntryRepository do

  include_context 'content entry repository'

  describe '#build system fields' do

    before { repository.with(type) }

    it 'gives a new entry its system defaults, but no timestamps' do
      built = repository.build({})

      expect(built[:_visible]).to be true
      expect(built[:_position]).to eq 0
      expect(built.attributes.key?(:created_at)).to be false
      expect(built.attributes.key?(:updated_at)).to be false
    end

    it 'keeps what the caller spelled out' do
      moment = Time.utc(2020, 1, 1)
      built  = repository.build(_visible: false, _position: 5, created_at: moment)

      expect(built[:_visible]).to be false
      expect(built[:_position]).to eq 5
      expect(built[:created_at]).to eq moment
    end

  end

  describe 'resolving select names on build' do

    let(:options_scope) { instance_double('Scope') }
    let(:option)        { instance_double('Option', _id: 42) }
    let(:options)       { instance_double('OptionRepository', scope: options_scope) }
    let(:field)         { instance_double('SelectField', name: 'category', persisted_name: 'category_id', type: :select, localized?: false, select_options: options) }
    let(:_fields)       { instance_double('Fields', selects: [field], required: [], belongs_to: [], many_to_many: [], dates_and_date_times: [], numbers: [], booleans: []) }
    let(:type)          { build_content_type('Articles', label_field_name: :title, fields: _fields, fields_by_name: {}, fields_with_default: []) }

    before do
      repository.with(type)
      allow(options_scope).to receive(:with_locale) { |&block| block.call }
      allow(options).to receive(:by_name).with('CMS').and_return(option)
      allow(options).to receive(:by_name).with('bogus').and_return(nil)
    end

    it 'resolves a name to the option id its store issued' do
      built = repository.build(category: 'CMS')

      expect(built[:category_id]).to eq 42
      expect(built.attributes.key?(:category)).to be false
    end

    it 'keeps an explicit id as given' do
      expect(repository.build(category_id: 7)[:category_id]).to eq 7
    end

    it 'takes an option object by its id' do
      expect(repository.build(category: instance_double('Option', _id: 9))[:category_id]).to eq 9
    end

    it 'clears the selection for a null' do
      built = repository.build(category: nil)

      expect(built.attributes.key?(:category_id)).to be true
      expect(built[:category_id]).to be_nil
    end

    it 'marks an unknown name and fails validation' do
      built = repository.build(category: 'bogus')

      expect(built.valid?).to be false
      expect(built.errors[:category]).to be_present
    end

    it 'refuses a name and an explicit id side by side' do
      built = repository.build(category: 'CMS', category_id: 7)

      expect(built.valid?).to be false
      expect(built.errors[:category]).to be_present
    end

    it 'accepts one key however indifferent access spells it' do
      built = repository.build({ category: 'CMS' }.with_indifferent_access)

      expect(built[:category_id]).to eq 42
      expect(built.valid?).to be true
    end

    it 'refuses one name spelled as two keys' do
      built = repository.build('category' => 'CMS', :category => 'CMS')

      expect(built.valid?).to be false
      expect(built.errors[:category]).to be_present
    end

    it 'refuses two explicit id keys' do
      built = repository.build('category_id' => 1, :category_id => 2)

      expect(built.valid?).to be false
      expect(built.errors[:category]).to be_present
    end

    context 'without an active locale' do

      let(:locale) { nil }
      let(:field)  { instance_double('SelectField', name: 'category', persisted_name: 'category_id', type: :select, localized?: true, select_options: options) }

      it 'resolves a scalar through the site default locale' do
        expect(repository.build(category: 'CMS')[:category_id]).to eq 42
        expect(options_scope).to have_received(:with_locale).with(:en)
      end

    end

    it 'refuses a hash for a select that is not localized' do
      built = repository.build(category: { en: 'CMS' })

      expect(built.valid?).to be false
      expect(built.errors[:category]).to be_present
    end

    context 'the select is required' do

      let(:_fields) { instance_double('Fields', selects: [field], required: [field], belongs_to: [], many_to_many: [], dates_and_date_times: [], numbers: [], booleans: []) }

      it 'adds one error to an unknown option, not a blank one as well' do
        built = repository.build(category: 'bogus')

        expect(built.valid?).to be false
        expect(built.errors[:category].size).to eq 1
      end

    end

  end

  describe '#build' do

    let(:attributes) { { title: 'Hello world' } }
    subject { repository.with(type).build(attributes) }

    it { expect(subject.title[:en]).to eq 'Hello world' }
    it { expect(subject.content_type).to eq type }

    context 'a select default naming no option' do

      let(:field) do
        instance_double('Field', name: 'visibility', persisted_name: 'visibility_id',
                        type: :select, localized?: false, default: 'nope')
      end
      let(:type) do
        build_content_type('Articles', label_field_name: :title, fields: _fields,
                           fields_with_default: [field])
      end

      it 'says which option it looked for' do
        allow(content_type_repository).to receive(:select_options).and_return([])

        expect { subject }.to raise_error(described_class::InvalidDefault,
                                          'articles.visibility has no option named "nope"')
      end

    end

  end

  describe '#dup' do

    it 'builds entities against the copy content type' do
      repository.with(type)
      repository.build({})

      copy          = repository.dup
      reloaded_type = build_content_type('Articles', _id: 1, fields: _fields, fields_with_default: [])
      copy.with(reloaded_type)

      expect(copy.build({}).content_type).to be(reloaded_type)
    end

  end

end
