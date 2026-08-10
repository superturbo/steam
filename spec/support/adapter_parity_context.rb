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

end
