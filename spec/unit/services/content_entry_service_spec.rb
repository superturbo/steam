require 'spec_helper'

describe Locomotive::Steam::ContentEntryService do

  let(:site)              { instance_double('Site', default_locale: 'en') }
  let(:locale)            { 'en' }
  let(:type_repository)   { instance_double('ContentTypeRepository') }
  let(:entry_repository)  { instance_double('Repository', site: site, locale: locale, content_type_repository: type_repository) }
  let(:service)           { described_class.new(type_repository, entry_repository, locale) }

  before do
    allow(entry_repository).to receive(:with).and_return(entry_repository)
    allow(entry_repository).to receive(:adapter).and_return(instance_double('Adapter', native_id?: false))
  end

  describe '#update_decorated_entry' do

    let(:title_field)  { instance_double('Field', name: :title, type: :string, is_relationship?: false, write_only?: false) }
    let(:email_field)  { instance_double('Field', name: :email, type: :email, is_relationship?: false, write_only?: false) }
    let(:fields)       { instance_double('Fields', json: [], selects: [], associations: []) }
    let(:content_type) do
      instance_double('ContentType', invalid_entry_names: [], fields_by_persisted_name: {}, slug: 'articles', fields: fields, label_field_name: :title,
                                     fields_by_name: { title: title_field, email: email_field }.with_indifferent_access,
                                     persisted_field_names: [:title, :email])
    end
    let(:entry) do
      Locomotive::Steam::ContentEntry.new(title: 'Old', email: 'jonas@example.lt').tap do |_entry|
        _entry.content_type         = content_type
        _entry.localized_attributes = {}
      end
    end
    let(:decorated) { Locomotive::Steam::Decorators::I18nDecorator.new(entry, locale) }

    before do
      allow(entry_repository).to receive(:content_type).and_return(content_type)
      allow(entry_repository).to receive(:resolve_selects) { |attributes| attributes }
      allow(entry_repository).to receive(:resolve_belongs_to) { |attributes| attributes }
      allow(entry_repository).to receive(:resolve_many_to_many) { |attributes| attributes }
    end

    it 'keeps the decorator attached to the written entity' do
      written = nil
      allow(entry_repository).to receive(:update) { |entity| written = entity }

      result = service.update_decorated_entry(decorated, 'title' => 'New')

      expect(result).to be(decorated)
      expect(result.__getobj__).to be(written)
      expect(result.__getobj__).not_to be(entry)
    end

    describe 'the log' do

      include_context 'filtered logs'

      let(:logged) { Hash.new { |hash, level| hash[level] = [] } }

      before do
        %i(debug info error).each do |level|
          allow(Locomotive::Common::Logger).to receive(level) { |message| logged[level] << message }
        end
      end

      it 'names a write by its type at info level, and adds its attributes, filtered by name, at debug level' do
        allow(entry_repository).to receive(:update)

        service.update_decorated_entry(decorated, 'title' => 'New title')

        expect(logged[:info]).to eq ['[articles] Entry persisted with success']
        expect(logged[:debug].join).to start_with('[articles] Entry attributes: ')
        expect(logged[:debug].join).to match(/"title"\s*=>\s*"New title"/).and match(/"email"\s*=>\s*"\[FILTERED\]"/)
        expect(logged[:debug].join).not_to include('jonas@example.lt')
      end

      it 'leaves the attributes out below the debug level' do
        allow(entry_repository).to receive(:update)
        logger = Locomotive::Common::Logger.instance.logger
        level, logger.level = logger.level, ::Logger::INFO

        service.update_decorated_entry(decorated, 'title' => 'New title')

        expect(logged[:debug]).to be_empty
      ensure
        logger.level = level
      end

      it 'names a failed write by its type and the codes of its failed fields at error level' do
        allow(entry_repository).to receive(:update) { |entity| entity.errors.add(:email, :invalid) }

        service.update_decorated_entry(decorated, 'title' => 'New title')

        expect(logged[:error]).to eq ['[articles] Failed to persist entry: email=invalid']
      end

      it 'logs each code of a failed field, and never an error text' do
        allow(entry_repository).to receive(:update) do |entity|
          entity.errors.add(:email, :blank)
          entity.errors.add(:email, :taken)
          entity.errors.add(:title, 'quotes New title')
        end

        service.update_decorated_entry(decorated, 'title' => 'New title')

        expect(logged[:error]).to eq ['[articles] Failed to persist entry: email=blank, email=taken, title=invalid']
      end

      it 'adds the attributes of a failed write, filtered by name, and its error messages at debug level' do
        allow(entry_repository).to receive(:update) { |entity| entity.errors.add(:email, :invalid) }

        service.update_decorated_entry(decorated, 'title' => 'New title')

        expect(logged[:debug].join).to start_with('[articles] Entry attributes: ')
        expect(logged[:debug].join).to match(/"title"\s*=>\s*"New title"/).and match(/"email"\s*=>\s*"\[FILTERED\]"/)
        expect(logged[:debug].join).to match(/"errors"\s*=>\s*\{"email"\s*=>\s*\["is invalid"\]\}/)
        expect(logged[:debug].join).not_to include('jonas@example.lt')
      end

      it "filters the attributes with the host's rules too" do
        allow(entry_repository).to receive(:update)

        described_class.new(type_repository, entry_repository, locale, log_rules: [:title]).update_decorated_entry(decorated, 'title' => 'New title')

        expect(logged[:debug].join).to match(/"title"\s*=>\s*"\[FILTERED\]"/)
      end

      it 'takes the rules of the request it is built for by the services' do
        env      = Rack::MockRequest.env_for('/', 'action_dispatch.parameter_filter' => [:title])
        services = Locomotive::Steam::Services.build_instance(Rack::Request.new(env))

        expect(services.content_entry.log_rules).to eq [:title]
      end

    end

  end

  describe '#create an entry whose label field is a password' do

    let(:secret_field) { instance_double('Field', name: :secret, type: :password, write_only?: true, is_relationship?: false) }
    let(:fields)       { instance_double('Fields', json: [], selects: [], associations: []) }
    let(:content_type) do
      instance_double('ContentType', invalid_entry_names: [], fields_by_persisted_name: {}, slug: 'accounts', fields: fields, label_field_name: :secret,
                                     fields_by_name: { secret: secret_field }.with_indifferent_access,
                                     persisted_field_names: [])
    end

    before do
      allow(type_repository).to receive(:by_slug).with('accounts').and_return(content_type)
      allow(entry_repository).to receive(:content_type).and_return(content_type)
      allow(entry_repository).to receive(:resolve_selects) { |attributes| attributes }
      allow(entry_repository).to receive(:resolve_belongs_to) { |attributes| attributes }
      allow(entry_repository).to receive(:resolve_many_to_many) { |attributes| attributes }
      allow(entry_repository).to receive(:build) do |attributes|
        Locomotive::Steam::ContentEntry.new(attributes).tap do |entry|
          entry.content_type         = content_type
          entry.localized_attributes = {}
          allow(entry).to receive(:base_url).and_return('/assets')
        end
      end
      allow(service).to receive(:validate) { |_, entry| entry.errors.add(:secret, :invalid); false }
    end

    it 'logs a failed write without the password' do
      logged = []
      allow(Locomotive::Common::Logger).to receive(:error) { |message| logged << message }

      service.create('accounts', { secret: 'plain-secret-1' })

      expect(logged.join).to include('[accounts] Failed to persist entry: secret=invalid')
      expect(logged.join).not_to include('plain-secret-1')
    end

    it 'names the type by its slug when given the type itself' do
      logged = []
      allow(Locomotive::Common::Logger).to receive(:error) { |message| logged << message }

      service.create(content_type, { secret: 'plain-secret-1' })

      expect(logged.join).to start_with('[accounts] Failed to persist entry')
    end

    it 'logs a key the visitor named but no field declares as _input' do
      logged = []
      allow(Locomotive::Common::Logger).to receive(:error) { |message| logged << message }

      service.create('accounts', { secret: 'plain-secret-1', tokenABC123: '1' })

      expect(logged.join).to include('[accounts] Failed to persist entry: ', '_input=invalid')
      expect(logged.join).not_to include('tokenABC123')
    end

  end

  describe '#create an entry whose stored schema declares a password unique' do

    let(:type_repository) { Locomotive::Steam::ContentTypeRepository.new(nil) }
    let(:adapter)         { Locomotive::Steam::MemoryAdapter.new(nil) }
    let(:fields)          { Locomotive::Steam::ContentTypeFieldRepository.new(adapter) }
    let(:content_type) do
      instance_double('ContentType', invalid_entry_names: [], fields_by_persisted_name: {}, slug: 'accounts', fields: fields, label_field_name: :email,
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
      allow(entry_repository).to receive(:resolve_many_to_many) { |attributes| attributes }
      allow(entry_repository).to receive(:build) do |attributes|
        Locomotive::Steam::ContentEntry.new(attributes).tap do |entry|
          entry.content_type         = content_type
          entry.localized_attributes = {}
        end
      end
    end

    it 'checks no password for uniqueness, leaving the refusal to the repository' do
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
      allow(entry_repository).to receive(:resolve_many_to_many) { |attributes| attributes }
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
      instance_double('ContentType', invalid_entry_names: [], fields_by_persisted_name: {}, slug: 'songs', fields: fields, label_field_name: :title,
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
      allow(entry_repository).to receive(:resolve_many_to_many) { |attributes| attributes }
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

        let(:unique_fields) { { title: instance_double('Field', name: 'title', persisted_name: 'title') } }

        before do
          allow(entry).to receive(:[]).with(:title).and_return('Hello world')
          allow(entry_repository).to receive(:in_locale).with(locale).and_return(entry_repository)
          allow(entry_repository).to receive(:exists?)
            .with('title' => 'Hello world', :'_id.ne' => entry_id, _visible: nil).and_return(true)
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
