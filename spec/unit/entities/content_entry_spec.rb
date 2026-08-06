require 'spec_helper'

describe Locomotive::Steam::ContentEntry do

  let(:fields)      { nil }
  let(:repository)  { instance_double('FieldRepository', all: fields) }
  let(:type)        { instance_double('ContentType', slug: 'articles', label_field_name: :title, fields: repository) }
  let(:attributes)  { { title: 'Hello world', _slug: 'hello-world' } }
  let(:content_entry) { described_class.new(attributes) }

  before do
    content_entry.content_type = type
    content_entry.site         = instance_double('Site', _id: 'site-42', timezone: ActiveSupport::TimeZone['UTC'])
  end

  describe '#change' do

    let(:fields) { [instance_double('Field', name: :title, type: :string, required: true)] }

    before do
      allow(type).to receive(:fields_by_name).and_return({ title: fields.first })
    end

    subject { content_entry.change('title' => 'Hello world!') }

    it { expect(subject.title).to eq('Hello world!') }
    it { expect(subject._slug).to eq('hello-world') }

    context 'a localized field' do

      let(:attributes) do
        { title: build_i18n_field(en: 'Hello', fr: 'Bonjour'), _slug: 'hello-world' }
      end

      before do
        content_entry.localized_attributes = { title: true }
        content_entry.site = instance_double('Site', timezone: ActiveSupport::TimeZone['UTC'],
                                                     default_locale: :en)
      end

      it 'writes one value into the site default locale, keeping the rest' do
        expect(subject[:title].translations).to eq('en' => 'Hello world!', 'fr' => 'Bonjour')
      end

      context 'while another locale is being edited' do
        subject { content_entry.change({ 'title' => 'Salut' }, :fr) }

        it { expect(subject[:title].translations).to eq('en' => 'Hello', 'fr' => 'Salut') }
      end

      context 'given a value per locale' do
        subject { content_entry.change('title' => { 'en' => 'Hi', 'fr' => 'Salut' }) }

        it 'keeps a field the store can write' do
          expect(subject[:title]).to be_a(Locomotive::Steam::Models::I18nField)
          expect(subject[:title].translations).to eq('en' => 'Hi', 'fr' => 'Salut')
        end
      end

      context 'a field the entry does not carry yet' do
        let(:attributes) { { _slug: 'hello-world' } }

        it { expect(subject[:title].translations).to eq('en' => 'Hello world!') }
      end

    end

  end

  describe '#valid?' do

    let(:field)           { instance_double('Field', name: :title, type: :string, persisted_name: :title) }
    let(:fields)          { [field] }
    let(:required_fields) { fields }

    before do
      allow(repository).to receive(:required).and_return(required_fields)
      allow(type).to receive(:fields_by_name).and_return(fields.index_by(&:name))
    end

    subject { content_entry.valid? }
    it { is_expected.to eq true }

    context 'missing attribute' do

      let(:attributes) { {} }
      it { is_expected.to eq false }
      it { subject; expect(content_entry.errors[:title]).to eq(["can't be blank"]) }
      it { subject; expect(content_entry.errors.empty?).to eq false }

    end

    context 'a required text field holding only spaces' do

      let(:attributes) { { title: '   ' } }

      it { is_expected.to eq false }
      it { subject; expect(content_entry.errors[:title]).to eq(["can't be blank"]) }

    end

    context 'a number field' do

      let(:field)           { instance_double('Field', name: :score, type: :integer, persisted_name: :score) }
      let(:required_fields) { [] }
      let(:attributes)      { { score: ' 12 ' } }

      it { is_expected.to eq true }

      it 'keeps the value the field would store' do
        subject
        expect(content_entry.attributes[:score]).to eq(12)
      end

      context 'holding a number no store can keep' do

        let(:field)      { instance_double('Field', name: :price, type: :float, persisted_name: :price) }
        let(:attributes) { { price: 10**400 } }

        it { subject; expect(content_entry.errors[:price]).to eq(['is invalid']) }

      end

      context 'holding text the field cannot read' do

        let(:attributes) { { score: 'abc' } }

        it { is_expected.to eq false }
        it { subject; expect(content_entry.errors[:score]).to eq(['is invalid']) }

        it 'leaves the value the caller sent' do
          subject
          expect(content_entry.attributes[:score]).to eq('abc')
        end

        it 'reports the same errors when asked twice' do
          content_entry.valid?
          expect { content_entry.valid? }.not_to change { content_entry.errors.to_hash }
        end

      end

      context 'localized' do

        let(:attributes) { { score: build_i18n_field(en: ' 12 ', fr: '13') } }

        before { content_entry.localized_attributes = { score: true } }

        it 'keeps the value of every locale' do
          subject
          expect(content_entry.attributes[:score].translations).to eq('en' => 12, 'fr' => 13)
        end

        context 'unreadable in one locale' do

          let(:attributes) { { score: build_i18n_field(en: '12', fr: 'abc') } }

          it { is_expected.to eq false }

          it 'leaves every locale as the caller sent it' do
            subject
            expect(content_entry.attributes[:score].translations).to eq('en' => '12', 'fr' => 'abc')
          end

        end

      end

      context 'required and set to zero' do

        let(:required_fields) { fields }
        let(:attributes)      { { score: 0 } }

        it { is_expected.to eq true }

      end

    end

    context 'a date field' do

      let(:field)           { instance_double('Field', name: :held_on, type: :date, persisted_name: :held_on) }
      let(:required_fields) { [] }
      let(:attributes)      { { held_on: Time.utc(2020, 1, 2, 2) } }

      before do
        content_entry.site = instance_double('Site',
          timezone: ActiveSupport::TimeZone['America/New_York'], default_locale: :en)
      end

      it 'keeps the day the moment falls on where the site stands' do
        subject
        expect(content_entry.attributes[:held_on]).to eq Date.new(2020, 1, 1)
      end

      context 'given a day rather than a moment' do

        let(:attributes) { { held_on: '2020-01-02' } }

        before { content_entry.site = instance_double('Site', timezone: nil) }

        it 'reads it without asking where the site stands' do
          subject
          expect(content_entry.attributes[:held_on]).to eq Date.new(2020, 1, 2)
        end

      end

    end

    context 'a json field' do

      let(:field)           { instance_double('Field', name: :payload, type: :json, persisted_name: :payload) }
      let(:required_fields) { [] }
      let(:attributes)      { { payload: ' {"a":1} ' } }

      it 'keeps the object the field reads out of what it was given' do
        subject
        expect(content_entry.attributes[:payload]).to eq('a' => 1)
      end

      context 'given what no field can read as an object' do

        let(:attributes) { { payload: '[1, 2, 3]' } }

        it { is_expected.to eq false }
        it { subject; expect(content_entry.errors[:payload]).to eq(['is invalid']) }

        it 'leaves the value the caller sent' do
          subject
          expect(content_entry.attributes[:payload]).to eq('[1, 2, 3]')
        end

      end

      context 'holding text in no readable encoding' do

        let(:attributes) { { payload: { 'a' => %(x\xFF) } } }

        it { subject; expect(content_entry.errors[:payload]).to eq(['is invalid']) }

      end

      context 'localized' do

        let(:attributes) { { payload: build_i18n_field(en: { 'a' => 1 }, fr: '{"a":2}') } }

        before do
          content_entry.localized_attributes = { payload: true }
          content_entry.site = instance_double('Site', timezone: ActiveSupport::TimeZone['UTC'],
                                                       default_locale: :en)
        end

        it 'reads each locale as an object of its own' do
          subject
          expect(content_entry.attributes[:payload].translations)
            .to eq('en' => { 'a' => 1 }, 'fr' => { 'a' => 2 })
        end

        context 'given a locale a bare value' do

          let(:attributes) { { payload: build_i18n_field(en: 1) } }

          it { subject; expect(content_entry.errors[:payload]).to eq(['is invalid']) }

        end

      end

      context 'required' do

        let(:required_fields) { fields }

        context 'holding an empty object' do
          let(:attributes) { { payload: {} } }
          it { subject; expect(content_entry.errors[:payload]).to eq(["can't be blank"]) }
        end

        context 'holding one name' do
          let(:attributes) { { payload: { 'a' => 1 } } }
          it { is_expected.to eq true }
        end

      end

    end

    context 'a required boolean field' do

      let(:field)      { instance_double('Field', name: :flag, type: :boolean, persisted_name: :flag) }
      let(:attributes) { { flag: false } }

      it { is_expected.to eq true }

      context 'never answered' do

        let(:attributes) { {} }

        it { subject; expect(content_entry.errors[:flag]).to eq(["can't be blank"]) }

      end

    end

    context 'a required localized boolean field' do

      let(:field)      { instance_double('Field', name: :flag, type: :boolean, persisted_name: :flag) }
      let(:attributes) { { flag: build_i18n_field(en: false, fr: true) } }

      before do
        content_entry.localized_attributes = { flag: true }
        content_entry.site = instance_double('Site', timezone: ActiveSupport::TimeZone['UTC'],
                                                     default_locale: :en)
      end

      it { is_expected.to eq true }

    end

    context 'a required association' do

      let(:field) { instance_double('Field', name: :maker, type: :belongs_to, persisted_name: 'maker_id') }

      let(:proxy) { Locomotive::Steam::Models::BelongsToAssociation.allocate }

      context 'the entry names none' do

        let(:attributes) { { maker: proxy, maker_id: nil } }

        it { subject; expect(content_entry.errors[:maker]).to eq(["can't be blank"]) }

      end

      context 'the entry names one' do

        let(:attributes) { { maker: proxy, maker_id: 42 } }

        it { is_expected.to eq true }

      end

      context 'many to many' do

        let(:field) { instance_double('Field', name: :topics, type: :many_to_many, persisted_name: 'topic_ids') }
        let(:proxy) { Locomotive::Steam::Models::ManyToManyAssociation.allocate }

        context 'holding no id' do

          let(:attributes) { { topics: proxy, topic_ids: [] } }

          it { subject; expect(content_entry.errors[:topics]).to eq(["can't be blank"]) }

        end

        context 'holding one' do

          let(:attributes) { { topics: proxy, topic_ids: [42] } }

          it { is_expected.to eq true }

        end

      end

      context 'has many' do

        let(:field)      { instance_double('Field', name: :reviews, type: :has_many, persisted_name: nil) }
        let(:attributes) { {} }

        it { is_expected.to eq true }

      end

    end

    context 'a required file field' do

      let(:field) { instance_double('Field', name: :cover, type: :file, persisted_name: :cover) }

      context 'the entry names no file' do

        let(:attributes) { { cover: nil } }

        it { subject; expect(content_entry.errors[:cover]).to eq(["can't be blank"]) }

      end

      context 'the entry names one' do

        let(:attributes) { { cover: 'poster.png' } }

        it { is_expected.to eq true }

      end

      context 'localized, named in the default locale only' do

        let(:attributes) { { cover: build_i18n_field(en: 'poster.png', fr: nil) } }

        before do
          content_entry.localized_attributes = { cover: true }
          content_entry.site = instance_double('Site', timezone: ActiveSupport::TimeZone['UTC'],
                                                       default_locale: :en)
        end

        it { is_expected.to eq true }

      end

    end

    context 'reading a select field' do

      let(:options)         { instance_double('SelectOptionRepository') }
      let(:field)           { instance_double('Field', name: :category, type: :select,
                                                       persisted_name: 'category_id', select_options: options) }
      let(:required_fields) { [] }
      let(:attributes)      { { category_id: 42 } }

      before do
        allow(options).to receive(:by_id_or_name).with(42)
          .and_return(instance_double('SelectOption', name: build_i18n_field(en: 'alpha')))
      end

      it 'resolves the option without keeping it' do
        expect(content_entry.category[:en]).to eq 'alpha'
        expect(content_entry.attributes['category_id']).to eq 42
        expect(content_entry.attributes).not_to have_key('category')
      end

    end

    context 'a required select field' do

      let(:options)    { instance_double('SelectOptionRepository') }
      let(:field)      { instance_double('Field', name: :category, type: :select,
                                                  persisted_name: 'category_id', select_options: options) }
      let(:attributes) { {} }

      before do
        allow(options).to receive(:by_id_or_name).and_return(nil)
        content_entry.site = instance_double('Site', timezone: ActiveSupport::TimeZone['UTC'],
                                                     default_locale: :en)
      end

      it { subject; expect(content_entry.errors[:category]).to eq(["can't be blank"]) }

      context 'holding an option' do

        let(:attributes) { { category_id: 42 } }

        before do
          allow(options).to receive(:by_id_or_name).with(42)
            .and_return(instance_double('SelectOption', name: build_i18n_field(en: 'alpha')))
        end

        it { is_expected.to eq true }

      end

    end

    context 'a required date field the value does not read as' do

      let(:field)      { instance_double('Field', name: :held_on, type: :date, persisted_name: :held_on) }
      let(:attributes) { { held_on: 'nope' } }

      it 'reports what is wrong with it, not that it is missing' do
        subject
        expect(content_entry.errors[:held_on]).to eq(['is invalid'])
      end

    end

    context 'a required localized field' do

      let(:attributes) { { title: build_i18n_field(en: 'Hello', fr: '') } }

      before do
        content_entry.localized_attributes = { title: true }
        content_entry.site = instance_double('Site', timezone: ActiveSupport::TimeZone['UTC'],
                                                     default_locale: :en)
      end

      it { is_expected.to eq true }

      context 'blank in the default locale' do

        let(:attributes) { { title: build_i18n_field(en: '', fr: 'Bonjour') } }

        it { subject; expect(content_entry.errors[:title]).to eq(["can't be blank"]) }

      end

    end

    describe 'adding a custom error message' do

      before { content_entry.errors.add(:title, 'is mandatory') }

      it { expect(content_entry.errors[:title]).to eq(['is mandatory']) }

    end

  end

  describe '#_label' do

    subject { content_entry._label }
    it { is_expected.to eq 'Hello world' }

  end

  describe '#content_type_slug' do

    subject { content_entry.content_type_slug }
    it { is_expected.to eq 'articles' }

  end

  describe '#to_hash' do

    let(:fields)      { [instance_double('TitleField', name: :title, type: :string, is_relationship?: false), instance_double('PictureField', name: :picture, type: :file, localized: true)] }
    let(:attributes)  { { id: 42, title: 'Hello world', _slug: 'hello-world', picture: Locomotive::Steam::Models::I18nField.new(:picture, fr: 'foo.png', en: 'bar.png'), custom_fields_recipe: ['hello', 'world'], _type: 'Entry' } }

    subject { content_entry.to_hash }

    before do
      allow(type).to receive(:fields_by_name).and_return({ title: fields.first, picture: fields.last })
      allow(type).to receive(:persisted_field_names).and_return([:title, :picture])
      allow(content_entry).to receive(:base_url).and_return('/assets')
    end

    it { expect(Set.new(subject.keys)).to eq(Set.new(['_id', '_position', '_visible', '_label', '_slug', 'content_type_slug', 'title', 'picture', 'created_at', 'updated_at'])) }

    context 'a field the entry never carried' do

      before { allow(type).to receive(:persisted_field_names).and_return([:title, :topic_ids]) }

      it 'reads as nothing rather than as a missing method' do
        expect(subject).to include('topic_ids' => nil)
      end

    end

    context 'when decorated' do

      let(:decorated) { Locomotive::Steam::Decorators::I18nDecorator.new(content_entry, :fr, :en) }

      before { allow(content_entry).to receive(:localized_attributes).and_return({ picture: true }) }

      subject { decorated.to_hash }

      it { expect(subject['picture'].url).to eq '/assets/foo.png' }

    end

  end

  describe '#as_json' do

    let(:fields)      { [instance_double('TitleField', name: :title, type: :string, is_relationship?: false), instance_double('PictureField', name: :picture, type: :file, localized: true)] }
    let(:attributes)  { { id: 42, title: 'Hello world', _slug: 'hello-world', picture: Locomotive::Steam::Models::I18nField.new(:picture, fr: 'foo.png', en: 'bar.png'), custom_fields_recipe: ['hello', 'world'], _type: 'Entry' } }
    let(:decorated)   { Locomotive::Steam::Decorators::I18nDecorator.new(content_entry, :fr, :en) }

    before do
      allow(type).to receive(:fields_by_name).and_return({ title: fields.first, picture: fields.last })
      allow(type).to receive(:persisted_field_names).and_return([:title, :picture])
      allow(content_entry).to receive(:localized_attributes).and_return({ picture: true })
      allow(content_entry).to receive(:base_url).and_return('/assets')
    end

    subject { decorated.as_json }

    it { expect(subject['picture']['url']).to eq '/assets/foo.png' }

    context 'includes a non dynamic attribute' do

      it "doesn't add it to the output" do
        content_entry['author'] = 'John Doe'
        expect(subject['author']).to eq nil
      end

    end

  end

  describe 'dynamic attributes' do

    let(:field_type)  { :string }
    let(:attributes)  { { my_field: value } }
    let(:field)       { instance_double('Field', name: :my_field, type: field_type) }

    before { allow(type).to receive(:fields_by_name).and_return(my_field: field) }

    subject { content_entry.my_field }

    describe 'unable to cast it' do

      let(:field_type)  { :float }
      let(:value)       { [] }
      it { is_expected.to eq nil }

    end

    context 'no provided value, should return nil' do

      let(:attributes)  { {} }
      it { is_expected.to eq nil }

    end

    context 'a string' do
      let(:value) { 'Hello world' }
      it { is_expected.to eq 'Hello world' }
      context 'localized' do
        let(:value) { build_i18n_field(en: 'Hello world', fr: 'Bonjour monde') }
        it { expect(subject.translations).to eq('en' => 'Hello world', 'fr' => 'Bonjour monde') }
      end

      it 'hands out its own copy' do
        subject << ' again'

        expect(content_entry.attributes[:my_field]).to eq 'Hello world'
      end
    end

    %i(text email color).each do |type|
      context "a #{type}" do
        let(:field_type) { type }
        let(:value)      { 'Hello world' }
        it { is_expected.to eq 'Hello world' }
      end
    end

    context 'a boolean' do
      let(:field_type) { :boolean }

      context 'true' do
        let(:value) { true }
        it { is_expected.to eq true }
      end

      context 'false' do
        let(:value) { false }
        it { is_expected.to eq false }
      end

      context 'localized' do
        let(:value) { build_i18n_field(en: true, fr: false) }
        it { expect(subject.translations).to eq('en' => true, 'fr' => false) }
      end
    end

    describe 'a value the store keeps as another type' do

      { 'text where a boolean goes' => [:boolean, 'true', :wrong_stored_type],
        'a number where text goes'  => [:string,  42,     :wrong_stored_type],
        'text no encoding reads'    => [:string,  %(caf\xFF), :invalid_encoding]
      }.each do |label, (type, held, reason)|
        context label do

          let(:field_type) { type }
          let(:value)      { held }

          it { is_expected.to be_nil }

          it "reports #{reason}" do
            events = capture_unread_values { subject }

            expect(events.map { |event| event.values_at(:field, :expected_type, :reason) })
              .to eq [['my_field', type.to_s, reason.to_s]]
          end

          it 'leaves the stored value alone' do
            subject

            expect(content_entry.attributes[:my_field]).to eq held
          end

        end
      end

      context 'in one locale of many' do

        let(:field_type) { :boolean }
        let(:value)      { build_i18n_field(en: true, fr: 'false') }

        it 'reads the locales it can and leaves the one it cannot empty' do
          expect(subject.translations).to eq('en' => true, 'fr' => nil)
        end

        it 'leaves the stored translations alone' do
          subject

          expect(content_entry.attributes[:my_field].translations).to eq('en' => true, 'fr' => 'false')
        end

      end

    end

    context 'an integer' do
      let(:field_type)  { :integer }
      let(:value)       { 42 }
      it { is_expected.to eq 42 }
      context 'localized' do
        let(:value) { build_i18n_field(en: 42, fr: 43) }
        it { expect(subject.translations).to eq('en' => 42, 'fr' => 43) }
      end
    end

    describe 'a number the store keeps as text' do

      let(:field_type)  { :integer }
      let(:value)       { '42' }

      it { is_expected.to be_nil }

      it 'leaves the stored value alone' do
        subject

        expect(content_entry.attributes[:my_field]).to eq '42'
      end

      it 'says which field went unread, and never what it held' do
        events = capture_unread_values { subject }

        expect(events.size).to eq 1
        expect(events.first).to eq(site_id: 'site-42', content_type: 'articles', entry_id: nil,
                                   field: 'my_field', locale: nil, expected_type: 'integer',
                                   actual_type: 'String', reason: 'wrong_stored_type')
      end

      context 'in one locale of many' do

        let(:value) { build_i18n_field(en: 42, fr: '43') }

        it 'reads the locales it can and leaves the one it cannot empty' do
          expect(subject.translations).to eq('en' => 42, 'fr' => nil)
        end

        it 'leaves the stored translations alone' do
          subject

          expect(content_entry.attributes[:my_field].translations).to eq('en' => 42, 'fr' => '43')
        end

        it 'says which locale went unread' do
          events = capture_unread_values { subject }

          expect(events.size).to eq 1
          expect(events.first).to include(field: 'my_field', locale: 'fr', reason: 'wrong_stored_type')
        end

      end

      context 'in every locale at once' do

        let(:value) { build_i18n_field('43') }

        it { expect(subject.translations).to eq({}) }

        it 'names no locale it cannot point at' do
          events = capture_unread_values { subject }

          expect(events.first).to include(locale: nil)
        end

      end

      it 'lets an error that is not about the value through' do
        allow(Locomotive::Steam::ContentFieldValues).to receive(:normalize_read).and_raise(NoMethodError)

        expect { subject }.to raise_error(NoMethodError)
      end

    end

    context 'a value no number can be read from' do
      let(:field_type)  { :integer }
      let(:value)       { 'abc' }

      it { is_expected.to eq nil }

      it 'leaves the stored value alone' do
        subject
        expect(content_entry.attributes[:my_field]).to eq 'abc'
      end

      context 'a fraction of one' do
        let(:value) { 12.7 }

        it { is_expected.to eq nil }

        it 'leaves the stored value alone' do
          subject
          expect(content_entry.attributes[:my_field]).to eq 12.7
        end
      end

      context 'a number of another kind' do
        let(:field_type) { :float }
        let(:value)      { BigDecimal('1.5') }

        it { is_expected.to eq nil }
      end
    end

    context 'a float' do
      let(:field_type)  { :float }
      let(:value)       { 42.0 }
      it { is_expected.to eql 42.0 }
      context 'given a whole number' do
        let(:value) { 42 }
        it { is_expected.to be_nil }
      end
      context 'localized' do
        let(:value) { build_i18n_field(en: 42.0, fr: 1.5) }
        it { expect(subject.translations).to eq('en' => 42.0, 'fr' => 1.5) }
      end
    end

    context 'a date' do
      let(:field_type)  { :date }
      let(:value)       { '2007/06/29' }
      let(:date)        { Date.parse('2007/06/29') }
      it { is_expected.to eq date }
      context 'localized' do
        let(:value) { build_i18n_field(en: '2007/06/29', fr: date) }
        it { expect(subject.translations).to eq('en' => date, 'fr' => date) }
        context 'with a single value for all the translations' do
          let(:value) { build_i18n_field('2007/06/29') }
          it { expect(subject[:fr]).to eq(date) }
          it { expect(subject[:en]).to eq(date) }
        end
      end
    end

    context 'a date time without a site to read it in' do

      before { content_entry.site = nil }

      let(:field_type) { :date_time }
      let(:value)      { '2007-06-29T10:00:00' }

      it 'says so instead of reading it as no value' do
        expect { subject }.to raise_error(Locomotive::Steam::ContentFieldValues::ConfigurationError)
      end

    end

    context 'a date time' do
      let(:field_type)  { :date_time }
      let(:value)       { '2007-06-29T10:00:00' }
      let(:time)        { Time.utc(2007, 6, 29, 10) }
      it { is_expected.to eql time }
      context 'localized' do
        let(:value) { build_i18n_field(en: '2007-06-29T10:00:00', fr: time) }
        it { expect(subject.translations).to eq('en' => time, 'fr' => time) }
      end
      context 'a date-only value resolves to midnight' do
        let(:value) { '2019-09-10' }
        it { is_expected.to eql Time.utc(2019, 9, 10) }
      end
      context 'an unparseable date-time value' do
        let(:value) { 'tomorrow' }
        it 'says the field went unread, without repeating what it held' do
          expect(Locomotive::Common::Logger).to receive(:warn) do |message|
            expect(message).to match(/Unable to read/)
            expect(message).not_to include 'tomorrow'
          end

          expect(subject).to be_nil
        end
      end
    end

    context 'a file' do
      let(:field_type)  { :file }
      let(:value)       { '/foo.png' }
      let(:attributes)  { { my_field: value, my_field_size: { 'default' => 42 } } }
      it { expect(subject.url).to eq('/foo.png') }
      it { expect(subject.size).to eq(42) }
      context 'localized' do
        let(:value) { build_i18n_field(en: '/foo-en.png', fr: '/foo-fr.png') }
        let(:attributes)  { { my_field: value, my_field_size: { 'en' => 42, 'fr' => 7 } } }
        it { expect(subject.translations[:en].url).to eq('/foo-en.png') }
        it { expect(subject.translations[:en].size).to eq(42) }
        it { expect(subject.translations[:fr].url).to eq('/foo-fr.png') }
        it { expect(subject.translations[:fr].size).to eq(7) }
      end
      context 'no file size provided' do
        let(:attributes)  { { my_field: value } }
        it { expect(subject.size).to eq(nil) }
      end
    end

    context 'a select' do
      let(:translations)  { instance_double('Translations', translations: { en: 'Category #1', fr: 'Categorie #1' }) }
      let(:option)        { instance_double('SelectOption', name: translations) }
      let(:options)       { instance_double('SelectOptions') }
      let(:field)         { instance_double('Field', name: :my_field, type: :select, select_options: options) }
      let(:attributes)    { { my_field_id: attribute } }

      context 'the attribute is not localized' do

        let(:option)    { instance_double('SelectOption', name: 'Category #1') }
        let(:attribute) { 42 }

        before { expect(options).to receive(:by_id_or_name).with(42).and_return(option) }

        it { expect(subject).to eq('Category #1') }
      end

      context 'the attribute is localized' do

        context 'the attribute has values in all the locales' do

          let(:attribute) { instance_double('FieldValue', default: nil, translations: true) }

          before do
            expect(attribute).to receive(:duplicate).with(:my_field).and_return(translations)
            expect(translations).to receive(:apply).and_return(translations)
          end

          it { expect(subject.translations).to eq({ en: 'Category #1', fr: 'Categorie #1' }) }

        end

        context 'the attribute has the same value in all the locales' do

          let(:attribute) { instance_double('FieldValue', default: 42, translations: true) }

          before { expect(translations).to receive(:duplicate).with(:my_field).and_return(translations) }
          before { expect(options).to receive(:by_id_or_name).with(42).and_return(option) }

          it { expect(subject.translations).to eq({ en: 'Category #1', fr: 'Categorie #1' }) }

        end

      end
    end

    context 'a password' do

      let(:field_type) { :password }
      let(:attributes) { { my_field_hash: BCrypt::Password.create('easyone') } }

      it { is_expected.to eq 'easyone' }

      context 'the store holds nothing' do

        { 'nothing at all' => nil, 'an empty text' => '' }.each do |label, held|
          context label do

            let(:attributes) { { my_field_hash: held } }

            it { is_expected.to be_nil }

            it 'reports nothing' do
              expect(capture_unread_values { subject }).to be_empty
            end

          end
        end

      end

      { 'text that is no hash'  => ['not-a-hash', :invalid_password_hash],
        'text of only spaces'   => ['   ',        :invalid_password_hash],
        'a number'              => [123,          :wrong_stored_type],
        'false'                 => [false,        :wrong_stored_type],
        'a list'                => [[],           :wrong_stored_type]
      }.each do |label, (held, reason)|
        context "the store holds #{label}" do

          let(:attributes) { { my_field_hash: held } }

          it { is_expected.to be_nil }

          it "reports #{reason}" do
            events = capture_unread_values { subject }

            expect(events.map { |event| event.values_at(:field, :reason) })
              .to eq [['my_field', reason.to_s]]
          end

        end
      end

    end

    context 'a json' do
      let(:field_type)  { :json }
      let(:value)       { '{"foo":42}' }
      it { is_expected.to eq({ 'foo' => 42 }) }
      context 'localized' do
        let(:value) { build_i18n_field(en: { 'foo' => 42 }, fr: '{"foo":43}') }
        it { expect(subject.translations).to eq('en' => { 'foo' => 42 }, 'fr' => { 'foo' => 43 }) }

        context 'holding a list in one locale' do
          let(:value) { build_i18n_field(en: { 'foo' => 42 }, fr: '[1, 2, 3]') }
          it { is_expected.to be_nil }
        end
      end
    end

  end

  def build_i18n_field(translations = {})
    Locomotive::Steam::Models::I18nField.new(:my_field, translations)
  end

  def capture_unread_values
    events   = []
    callback = ->(*, payload) { events << payload }

    ActiveSupport::Notifications.subscribed(callback, 'steam.entries.unread_value') { yield }

    events
  end

end
