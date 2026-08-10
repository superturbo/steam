RSpec.shared_context 'adapter parity dataset access' do

  let(:site_repository) { Locomotive::Steam::SiteRepository.new(adapter) }
  let(:site)            { site_repository.by_handle_or_domain('adapter-parity', nil) }
  let(:type_repository) { Locomotive::Steam::ContentTypeRepository.new(adapter, site, AdapterParityFixture::LOCALE) }

  def slugs(conditions)
    repository = Locomotive::Steam::ContentEntryRepository.new(
      adapter, site, AdapterParityFixture::LOCALE, type_repository)

    repository.with(type_repository.by_slug('specimens')).all(conditions).map do |entry|
      entry._slug[AdapterParityFixture::LOCALE]
    end
  end

  # Each store issues its own option ids, so the fixture cannot spell one.
  def option_id(field, name)
    type_repository.select_options(type_repository.by_slug('specimens'), field)
                   .detect { |option| option.name[:en] == name }._id
  end

  def specimens(locale = AdapterParityFixture::LOCALE)
    types = Locomotive::Steam::ContentTypeRepository.new(adapter, site, locale)

    Locomotive::Steam::ContentEntryRepository.new(adapter, site, locale, types)
      .with(types.by_slug('specimens'))
  end

  def makers
    types = Locomotive::Steam::ContentTypeRepository.new(adapter, site, AdapterParityFixture::LOCALE)

    Locomotive::Steam::ContentEntryRepository.new(adapter, site, AdapterParityFixture::LOCALE, types)
      .with(types.by_slug('makers'))
  end

end

RSpec.shared_context 'adapter parity repository writing' do

  def another_specimens_repository
    Locomotive::Steam::ContentEntryRepository.new(
      adapter, site, AdapterParityFixture::LOCALE, type_repository)
      .with(type_repository.by_slug('specimens'))
  end

  def build_specimen(attributes = {})
    specimens.build({ name: 'Created', score: 41,
                      category_id: option_id(:category, 'alpha') }.merge(attributes))
  end

  # Only Filesystem sanitizes a new entry into a slug, so reads here go
  # through the id both stores do issue.
  def create_specimen(attributes = {})
    specimens.create(build_specimen(attributes)).tap { |entry| written << entry }
  end

  let(:written) { [] }

  after do
    written.each { |entry| specimens.delete(entry) if entry._id && specimens.find(entry._id) }
  end

  # Seed a value that predates repository validation.
  def store_specimen(attributes = {})
    build_specimen(attributes).tap do |entity|
      specimens.adapter.create(specimens.send(:mapper), specimens.scope, entity)
      written << entity
    end
  end

end

RSpec.shared_context 'adapter parity service access' do

  let(:entries) do
    Locomotive::Steam::ContentEntryRepository.new(
      adapter, site, AdapterParityFixture::LOCALE, type_repository)
  end

  let(:service) do
    Locomotive::Steam::ContentEntryService.new(
      type_repository, entries, AdapterParityFixture::LOCALE)
  end

end

RSpec.shared_context 'adapter parity service writing' do

  let(:valid) { { name: 'Ada', email: 'ada@example.com', message: 'Hello' } }

  let(:writable_types) { %w(specimens submissions) }

  let(:original_ids) do
    writable_types.to_h { |type| [type, service.all(type).map(&:_id)] }
  end

  before { original_ids }

  # A failed create may leave a persisted entry, so remove everything
  # added here.
  after do
    writable_types.each do |type|
      service.all(type).each do |entry|
        service.delete(type, entry._id) unless original_ids.fetch(type).include?(entry._id)
      end
    end
  end

  def entries_of(type_slug)
    Locomotive::Steam::ContentEntryRepository.new(
      adapter, site, AdapterParityFixture::LOCALE, type_repository)
      .with(type_repository.by_slug(type_slug))
  end

  def create_linked
    service.create('specimens',
                   name: 'Linked',
                   category_id: option_id(:category, 'alpha'),
                   maker_id: entries_of('makers').by_slug('maker-one')._id,
                   topic_ids: [entries_of('topics').by_slug('topic-a')._id])
  end

  # Use a fresh mapper so cached entities cannot hide persisted state.
  def stored_specimen(id)
    entries_of('specimens').find(id)
  end

  def links_of(id)
    stored = stored_specimen(id)

    [stored.maker&.name, stored.topics.all.map(&:name)]
  end

  def service_in(locale)
    types = Locomotive::Steam::ContentTypeRepository.new(adapter, site, locale)

    Locomotive::Steam::ContentEntryService.new(
      types, Locomotive::Steam::ContentEntryRepository.new(adapter, site, locale, types), locale)
  end

  def localized_specimen
    service.create('specimens', name: 'Localized', category_id: option_id(:category, 'alpha'),
                                topic_ids: [], title: { 'en' => 'Hello', 'fr' => 'Bonjour' })
  end

  def readable_specimen(attributes)
    service.create('specimens', { name: 'Readable', topic_ids: [],
                                  category_id: option_id(:category, 'alpha') }.merge(attributes))
  end

  def ids_matching(conditions)
    entries_of('specimens').all(conditions).map(&:_id)
  end

end
