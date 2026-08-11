require_relative '../../lib/locomotive/steam/adapters/filesystem.rb'

RSpec.shared_context 'content entry repository' do

  let(:_fields) { instance_double('Fields', selects: [], belongs_to: [], many_to_many: [], dates_and_date_times: [], numbers: [], booleans: []) }
  let(:type)    { build_content_type('Articles', label_field_name: :title, localized_names: %w(title), fields: _fields, fields_by_name: { title: instance_double('Field', name: :title, type: :string) }, fields_with_default: []) }
  let(:entries) { [{ content_type_id: 1, _position: 0, _label: 'Update #1', title: { fr: 'Mise a jour #1' }, text: { en: 'added some free stuff', fr: 'phrase FR' }, date: '2009/05/12', category: 'General' }] }
  let(:locale)  { :en }
  let(:site)    { instance_double('Site', _id: 1, default_locale: :en, locales: %i(en fr), timezone: ActiveSupport::TimeZone['UTC']) }
  let(:adapter) { Locomotive::Steam::FilesystemAdapter.new(nil) }

  let(:content_type_repository) { instance_double('ContentTypeRepository') }
  let(:repository)  { described_class.new(adapter, site, locale, content_type_repository) }

  # Mirror the YAML loader's implicit visibility.
  def loaded(list)
    list.map { |attributes| { _visible: true }.merge(attributes) }
  end

  # ContentType#fields_by_name is indifferent; the double has to be too.
  def build_content_type(name, attributes = {})
    defaults = {
      _id:                    1,
      slug:                   name.to_s.downcase,
      order_by:               nil,
      localized_names:        [],
      select_fields:          [],
      association_fields:     [],
      fields_by_name:         {}
    }

    attributes = defaults.merge(attributes)
    attributes[:fields_by_name] = attributes[:fields_by_name].with_indifferent_access

    instance_double(name, attributes)
  end

  before do
    allow(adapter).to receive(:collection).and_return(loaded(entries))
    adapter.cache = NoCacheStore.new
  end

end
