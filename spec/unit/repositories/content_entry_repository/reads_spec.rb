require 'spec_helper'

require_relative '../../../support/content_entry_repository_context'

describe Locomotive::Steam::ContentEntryRepository do

  include_context 'content entry repository'

  describe 'lazy read wiring' do

    before { repository.with(type) }

    it '#first fetches a single entry (query#first), not #all' do
      dataset = double('dataset', first: :entry)
      allow(dataset).to receive(:all)
      allow(repository).to receive(:query).and_return(dataset)

      expect(repository.first).to eq :entry
      expect(dataset).to have_received(:first)
      expect(dataset).not_to have_received(:all)
    end

    it '#exists? checks #empty?, not #all.size' do
      dataset = double('dataset', empty?: false)
      allow(repository).to receive(:query).and_return(dataset)
      allow(dataset).to receive(:all)

      expect(repository.exists?).to be true
      expect(dataset).to have_received(:empty?)
      expect(dataset).not_to have_received(:all)
    end

  end

  describe '#all' do

    let(:conditions) { nil }

    subject { repository.with(type).all(conditions) }

    it { expect(subject.size).to eq 1 }

    describe 'first element' do

      subject { repository.with(type).all(conditions).first }

      it { expect(subject.class).to eq Locomotive::Steam::ContentEntry }
      it { expect(subject._label.translations).to eq('en' => 'Update #1', 'fr' => 'Mise a jour #1') }
      it { expect(subject._slug.translations).to eq('en' => 'update-number-1', 'fr' => 'mise-a-jour-number-1') }
      it { expect(subject.title.translations).to eq('en' => 'Update #1', 'fr' => 'Mise a jour #1') }
      it { expect(subject.content_type).to eq type }

    end

    # The slug is generated metadata and covers every locale, while the label
    # the author never translated stays untranslated.
    describe 'an entry whose localized label has one locale' do

      let(:entries) { [{ content_type_id: 1, _position: 0, _label: 'English only' }] }

      subject { repository.with(type).all.first }

      it { expect(subject.title.translations).to eq('en' => 'English only') }
      it { expect(subject._slug.translations).to eq('en' => 'english-only', 'fr' => 'english-only') }

    end

    describe 'including also the not visible entries' do

      let(:entries) { [
        { content_type_id: 1, _position: 0, _label: 'Update #1', title: { fr: 'Mise a jour #1' }, text: { en: 'added some free stuff', fr: 'phrase FR' }, date: '2009/05/12', category: 'General' },
        { content_type_id: 1, _position: 1, _label: 'Update #2 [HIDDEN]', title: { fr: 'Mise a jour #1' }, text: { en: 'added some free stuff', fr: 'phrase FR' }, date: '2009/05/12', category: 'General', _visible: false }
      ] }

      let(:conditions) { { _visible: nil } }

      it { expect(subject.size).to eq 2 }

    end

  end

  describe 'reading a stored entry' do

    let(:type) do
      build_content_type('Articles', label_field_name: :title, fields: _fields, fields_with_default: [],
                         fields_by_name: { title:      instance_double('Field', name: :title, type: :string),
                                           held_on:    instance_double('Field', name: :held_on, type: :date,
                                                                       persisted_name: 'held_on'),
                                           launched_at: instance_double('Field', name: :launched_at, type: :date_time,
                                                                        persisted_name: 'launched_at') })
    end

    let(:stored)  { Date.new(2013, 2, 11) }
    let(:entries) do
      [{ content_type_id: 1, _position: 0, _label: 'Stored', held_on: stored,
         launched_at: Time.new(2012, 6, 6, 14, 0, 0, '+02:00') }]
    end

    subject { repository.with(type).all.first }

    context 'a date the store wrote as a time' do
      let(:stored) { Time.utc(2013, 2, 11) }
      it { expect(subject[:held_on]).to eql Date.new(2013, 2, 11) }
    end

    context 'an already normalized date' do
      let(:stored) { Date.new(2013, 2, 11) }
      it('is left alone') { expect(subject[:held_on]).to eql Date.new(2013, 2, 11) }
    end

    # Text is not an adapter date representation, so deserialization leaves it unchanged.
    { 'a date spelled out'     => '2013-02-11',
      'text that names no day' => 'not a date' }.each do |label, held|
      context label do
        let(:stored) { held }

        it 'stays exactly as the store holds it' do
          expect(subject[:held_on]).to eq held
        end
      end
    end

    context 'a field the store never wrote' do
      let(:entries) { [{ content_type_id: 1, _position: 0, _label: 'Stored' }] }

      it { expect(subject.attributes).not_to have_key('held_on') }
    end

    it 'reads a time as UTC' do
      expect(subject[:launched_at]).to eql Time.utc(2012, 6, 6, 12)
      expect(subject[:launched_at]).to be_utc
    end

    context 'without a site' do
      let(:site) { nil }

      it 'reads what the store holds all the same' do
        expect(subject[:launched_at]).to eql Time.utc(2012, 6, 6, 12)
        expect(subject[:held_on]).to eql Date.new(2013, 2, 11)
      end
    end

    it 'does not read a built entry the same way' do
      built = repository.with(type).build(held_on: Time.utc(2013, 2, 11))

      expect(built[:held_on]).to be_a(Time)
    end

    it 'keeps the site out of what the store is given' do
      expect(repository.with(type).send(:mapper).serialize(subject)).not_to have_key(:site)
    end

    context 'a localized file field' do

      let(:type) do
        build_content_type('Articles', label_field_name: :title, fields: _fields, fields_with_default: [],
                           localized_names: %w(photo),
                           fields_by_name: { photo: instance_double('Field', name: :photo, type: :file) })
      end
      let(:entries) { [{ content_type_id: 1, _position: 0, _label: 'Stored', photo: { en: 'photo.jpg' } }] }

      it 'serializes the stored filename after the accessor presents a file' do
        entry = repository.with(type).all.first

        expect(entry.photo[:en]).to respond_to(:url)
        expect(repository.with(type).send(:mapper).serialize(entry)['photo']).to eq('en' => 'photo.jpg')
      end

    end

    # A day names no instant, so nothing here picks one for it.
    context 'a date in a date time field' do
      let(:entries) do
        [{ content_type_id: 1, _position: 0, _label: 'Stored', launched_at: Date.new(2013, 2, 11) }]
      end

      it { expect(subject[:launched_at]).to eql Date.new(2013, 2, 11) }
    end

    context 'a localized date' do
      let(:type) do
        build_content_type('Articles', label_field_name: :title, fields: _fields, fields_with_default: [],
                           localized_names: %w(held_on),
                           fields_by_name: { title:   instance_double('Field', name: :title, type: :string),
                                             held_on: instance_double('Field', name: :held_on, type: :date,
                                                                      persisted_name: 'held_on') })
      end

      let(:entries) do
        [{ content_type_id: 1, _position: 0, _label: 'Stored', held_on: { en: Time.utc(2013, 2, 11), fr: nil } }]
      end

      it 'reads the locales the store wrote and invents none' do
        expect(subject[:held_on].translations).to eq('en' => Date.new(2013, 2, 11), 'fr' => nil)
      end

      context 'one value standing for every locale' do
        let(:entries) do
          [{ content_type_id: 1, _position: 0, _label: 'Stored', held_on: Time.utc(2013, 2, 11) }]
        end

        it 'reads it once and leaves the locales unmaterialized' do
          expect(subject[:held_on][:fr]).to eql Date.new(2013, 2, 11)
          expect(subject[:held_on].translations).to be_empty
        end
      end
    end

  end

  describe '#exists?' do

    let(:conditions) { {} }
    subject { repository.with(type).exists?(conditions) }

    it { expect(subject).to eq true }

    context 'more specific conditions' do

      let(:conditions) { { '_slug' => 'update-number-1' } }
      it { expect(subject).to eq true }

    end

    context 'conditions which do match any entries' do

      let(:conditions) { { '_slug' => 'foo' } }
      it { expect(subject).to eq false }

    end

  end

  describe '#by_slug' do

    let(:slug) { nil }
    subject { repository.with(type).by_slug(slug) }

    it { is_expected.to eq nil }

    context 'existing slug' do
      let(:slug) { 'update-number-1' }
      it { expect(subject.title.translations).to eq('en' => 'Update #1', 'fr' => 'Mise a jour #1') }
    end

  end

  describe '#group_by_select_option' do

    let(:type) { nil }
    let(:name) { nil }

    subject { repository.with(type).group_by_select_option(name) }

    it { is_expected.to eq({}) }

    context 'select field' do

      let(:fields) do
        {
          title:    instance_double('TitleField', name: :title, type: :string),
          category: instance_double('SelectField', name: :category, type: :select, localized: true, select_options: [])
        }
      end
      let(:type) { build_content_type('Articles', order_by: '_position asc', label_field_name: :title, localized_names: %w(title category_id), fields: _fields, fields_by_name: fields, fields_with_default: []) }
      let(:name) { :category }

      let(:options) {
        [
          instance_double('SelectOption1', _id: '0', name: instance_double('I18nField', :[] => 'cooking', translations: { 'en' => 'cooking' })),
          instance_double('SelectOption2', _id: '1', name: instance_double('I18nField', :[] => 'wine', translations: { 'en' => 'wine' })),
          instance_double('SelectOption3', _id: '2', name: instance_double('I18nField', :[] => 'bread', translations: { 'en' => 'bread' }))
        ]
      }

      let(:entries) do
        [
          { content_type_id: 1, _position: 0, _label: 'Recipe #1', category_id: { 'en' => '0' } },
          { content_type_id: 1, _position: 1, _label: 'Recipe #2', category_id: { 'en' => '2' } },
          { content_type_id: 1, _position: 2, _label: 'Recipe #3', category_id: { 'en' => '2' } },
          { content_type_id: 1, _position: 3, _label: 'Recipe #4', category_id: { 'en' => '42' } } # unknown category
        ]
      end

      before {
        allow(content_type_repository).to receive(:select_options).and_return(options)
        %w(cooking wine bread).each_with_index do |name, position|
          allow(fields[:category].select_options).to receive(:by_id_or_name).with(position.to_s).and_return(options.at(position))
        end
        allow(fields[:category].select_options).to receive(:by_id_or_name).with('42').and_return(nil)
      }

      it { expect(subject.size).to eq 4 }
      it { expect(subject.map { |h| h[:name] }).to eq ['cooking', 'wine', 'bread', nil] }
      it { expect(subject.map { |h| h[:entries].size }).to eq [1, 0, 2, 1] }

    end

  end

end
