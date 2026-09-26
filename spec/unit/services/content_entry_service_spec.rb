require 'spec_helper'

describe Locomotive::Steam::ContentEntryService do

  let(:site)              { instance_double('Site', default_locale: 'en') }
  let(:locale)            { 'en' }
  let(:type_repository)   { instance_double('ContentTypeRepository') }
  let(:entry_repository)  { instance_double('Repository', site: site, locale: locale, content_type_repository: type_repository) }
  let(:service)           { described_class.new(type_repository, entry_repository, locale) }

  before { allow(entry_repository).to receive(:with).and_return(entry_repository) }

  describe '#update_decorated_entry' do

    let(:title_field)  { instance_double('Field', name: :title, type: :string, is_relationship?: false, write_only?: false) }
    let(:fields)       { instance_double('Fields', json: [], selects: [], associations: []) }
    let(:content_type) do
      instance_double('ContentType', invalid_entry_names: [], slug: 'articles', fields: fields, label_field_name: :title,
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
      allow(entry_repository).to receive(:resolve_belongs_to) { |attributes| attributes }
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

  describe '#create an entry whose label field is a password' do

    let(:secret_field) { instance_double('Field', name: :secret, type: :password, write_only?: true, is_relationship?: false) }
    let(:fields)       { instance_double('Fields', json: [], selects: [], associations: []) }
    let(:content_type) do
      instance_double('ContentType', invalid_entry_names: [], slug: 'accounts', fields: fields, label_field_name: :secret,
                                     fields_by_name: { secret: secret_field }.with_indifferent_access,
                                     persisted_field_names: [])
    end

    before do
      allow(type_repository).to receive(:by_slug).with('accounts').and_return(content_type)
      allow(entry_repository).to receive(:content_type).and_return(content_type)
      allow(entry_repository).to receive(:resolve_selects) { |attributes| attributes }
      allow(entry_repository).to receive(:resolve_belongs_to) { |attributes| attributes }
      allow(entry_repository).to receive(:build) do |attributes|
        Locomotive::Steam::ContentEntry.new(attributes).tap do |entry|
          entry.content_type         = content_type
          entry.localized_attributes = {}
          allow(entry).to receive(:base_url).and_return('/assets')
        end
      end
      allow(service).to receive(:validate) { |_, entry| entry.errors.add(:email, :blank); false }
    end

    it 'logs a failed write without the password' do
      logged = []
      allow(Locomotive::Common::Logger).to receive(:error) { |message| logged << message }

      service.create('accounts', { secret: 'plain-secret-1' })

      expect(logged.join).to include('Failed to persist entry')
      expect(logged.join).not_to include('plain-secret-1')
    end

  end

  describe '#create an entry whose stored schema declares a password unique' do

    let(:type_repository) { Locomotive::Steam::ContentTypeRepository.new(nil) }
    let(:adapter)         { Locomotive::Steam::MemoryAdapter.new(nil) }
    let(:fields)          { Locomotive::Steam::ContentTypeFieldRepository.new(adapter) }
    let(:content_type) do
      instance_double('ContentType', invalid_entry_names: [], slug: 'accounts', fields: fields, label_field_name: :email,
                                     fields_by_name: fields.all.index_by(&:name).with_indifferent_access,
                                     persisted_field_names: ['email'])
    end

    before do
      allow(adapter).to receive(:collection)
        .and_return([{ name: 'email', type: 'email' }, { name: 'secret', type: 'password', unique: true }])
      allow(type_repository).to receive(:by_slug).with('accounts').and_return(content_type)
      allow(entry_repository).to receive(:content_type).and_return(content_type)
      allow(entry_repository).to receive(:resolve_selects) { |attributes| attributes }
      allow(entry_repository).to receive(:resolve_belongs_to) { |attributes| attributes }
      allow(entry_repository).to receive(:build) do |attributes|
        Locomotive::Steam::ContentEntry.new(attributes).tap do |entry|
          entry.content_type         = content_type
          entry.localized_attributes = {}
        end
      end
    end

    it 'reaches create without reading the password' do
      expect(entry_repository).to receive(:create)

      entry = service.create('accounts', { email: 'john@doe.net', secret: 'easyone' })

      expect(entry.errors).to be_empty
    end

  end

  describe '#create against a stored schema no loader checked' do

    let(:adapter)      { Locomotive::Steam::MemoryAdapter.new(nil) }
    let(:fields)       { Locomotive::Steam::ContentTypeFieldRepository.new(adapter) }
    let(:content_type) { Locomotive::Steam::ContentType.new(slug: 'accounts', label_field_name: 'email', entries_custom_fields: fields) }

    before do
      allow(adapter).to receive(:collection).and_return([
        { name: 'email', type: 'string' }, { name: '_visible', type: 'string' },
        { name: 'secret', type: 'password' }, { name: 'secret_hash', type: 'string' },
        { name: 'created_by_id', type: 'string' }
      ])
      allow(type_repository).to receive(:by_slug).with('accounts').and_return(content_type)
      allow(type_repository).to receive(:look_for_unique_fields).and_return({})
      allow(entry_repository).to receive(:content_type).and_return(content_type)
      allow(entry_repository).to receive(:resolve_selects) { |attributes| attributes }
      allow(entry_repository).to receive(:resolve_belongs_to) { |attributes| attributes }
      allow(entry_repository).to receive(:build) do |attributes|
        Locomotive::Steam::ContentEntry.new(attributes).tap do |entry|
          entry.content_type         = content_type
          entry.localized_attributes = {}
        end
      end
    end

    it 'refuses a declared field that claims a reserved name' do
      expect(entry_repository).not_to receive(:create)

      entry = service.create('accounts', { email: 'john@doe.net', _visible: 'false' })

      expect(entry.errors[:_visible]).to eq ['is invalid']
      expect(entry.attributes).not_to have_key(:_visible)
    end

    it 'refuses a declared field that claims an attribute the Engine keeps' do
      expect(entry_repository).not_to receive(:create)

      entry = service.create('accounts', { email: 'john@doe.net', created_by_id: 'forged' })

      expect(entry.errors[:created_by_id]).to eq ['is invalid']
      expect(entry.attributes).not_to have_key(:created_by_id)
    end

    it 'refuses every input of the fields whose names collide' do
      expect(entry_repository).not_to receive(:create)

      entry = service.create('accounts', { email: 'john@doe.net', secret: 'easyone1', secret_hash: 'forged' })

      expect(entry.errors.to_hash.keys).to match_array %w(secret secret_hash)
      expect(entry.attributes.keys).to eq ['email']
    end

  end

  describe '#create an entry with an uploaded file' do

    let(:title_field)  { instance_double('Field', name: :title, type: :string, persisted_name: 'title', write_only?: false, is_relationship?: false) }
    let(:cover_field)  { instance_double('Field', name: :cover, type: :file, persisted_name: 'cover', write_only?: false, is_relationship?: false) }
    let(:secret_field) { instance_double('Field', name: :secret, type: :password, persisted_name: nil, write_only?: true, is_relationship?: false) }
    let(:price_field)  { instance_double('Field', name: :price, type: :money, persisted_name: 'price', write_only?: false, is_relationship?: false) }
    let(:tint_field)   { instance_double('Field', name: :tint, type: :color, persisted_name: 'tint', write_only?: false, is_relationship?: false) }
    let(:fields)       { instance_double('Fields', json: [], selects: [], associations: [], required: []) }
    let(:content_type) do
      instance_double('ContentType', invalid_entry_names: [], slug: 'songs', fields: fields, label_field_name: :title,
                                     fields_by_name: { title: title_field, cover: cover_field, secret: secret_field,
                                                       price: price_field, tint: tint_field }.with_indifferent_access,
                                     persisted_field_names: ['title'])
    end

    before do
      allow(type_repository).to receive(:by_slug).with('songs').and_return(content_type)
      allow(type_repository).to receive(:look_for_unique_fields).and_return({})
      allow(entry_repository).to receive(:content_type).and_return(content_type)
      allow(entry_repository).to receive(:resolve_selects) { |attributes| attributes }
      allow(entry_repository).to receive(:resolve_belongs_to) { |attributes| attributes }
      allow(entry_repository).to receive(:build) do |attributes|
        Locomotive::Steam::ContentEntry.new(attributes).tap do |entry|
          entry.content_type         = content_type
          entry.localized_attributes = {}
        end
      end
    end

    let(:upload) { { filename: 'cover.png', tempfile: 'an uploaded file' } }

    it 'refuses it before it reaches the entry' do
      expect(entry_repository).not_to receive(:create)

      entry = service.create('songs', { title: 'Song', cover: upload })

      expect(entry.errors[:cover]).to eq ['is invalid']
      expect(entry.attributes).not_to have_key(:cover)
    end

    it 'refuses a password hash before it reaches the entry' do
      expect(entry_repository).not_to receive(:create)

      entry = service.create('songs', { title: 'Song', secret_hash: '$2a$04$' + 'a' * 53 })

      expect(entry.errors[:secret_hash]).to eq ['is invalid']
      expect(entry.attributes).not_to have_key(:secret_hash)
    end

    it 'writes a color by its name' do
      expect(entry_repository).to receive(:create)

      entry = service.create('songs', { title: 'Song', tint: '#ff0000' })

      expect(entry.errors).to be_empty
      expect(entry.attributes[:tint]).to eq '#ff0000'
    end

    it 'refuses a field of a type this host does not write' do
      expect(entry_repository).not_to receive(:create)

      entry = service.create('songs', { title: 'Song', price: '9.99' })

      expect(entry.errors[:price]).to eq ['is invalid']
      expect(entry.attributes).not_to have_key(:price)
    end

    context 'a required file' do

      let(:fields) { instance_double('Fields', json: [], selects: [], associations: [], required: [cover_field]) }

      it 'is refused and still missing' do
        entry = service.create('songs', { title: 'Song', cover: upload })

        expect(entry.errors[:cover]).to eq ['is invalid', "can't be blank"]
      end

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
