require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'
require_relative '../../support/adapter_parity_fixture'

# Pin the Mongo representation so parity cannot pass on a shared seed bug.
describe 'Adapter parity seed' do

  before(:all) { AdapterParityFixture.seed_mongodb! }
  after(:all)  { AdapterParityFixture.cleanup! }

  let(:entries) { AdapterParityFixture.mongodb_client['locomotive_content_entries'] }

  it 'writes the site under the names Engine stores, not the Wagon ones' do
    site = AdapterParityFixture.mongodb_client['locomotive_sites']
                               .find('_id' => AdapterParityFixture::SITE_ID).first

    expect(site).to include('handle' => 'adapter-parity', 'timezone_name' => 'UTC')
    expect(site).not_to have_key('subdomain')
    expect(site).not_to have_key('timezone')
    expect(site['domains']).to eq %w(adapter-parity.example.com)
  end

  def document(slug)
    entries.find('site_id' => AdapterParityFixture::SITE_ID, "_slug.#{AdapterParityFixture::LOCALE}" => slug).first
  end

  it 'writes a page tree Engine can walk' do
    pages = AdapterParityFixture.mongodb_client['locomotive_pages']
                                .find('site_id' => AdapterParityFixture::SITE_ID).to_a
                                .each_with_object({}) { |page, all| all[page['fullpath']['en']] = page }

    expect(pages['index']).to include('depth' => 0, 'parent_ids' => [])
    expect(pages['index']).not_to have_key('parent_id')
    expect(pages['about']['depth']).to eq 1
    expect(pages['about']['parent_id']).to eq pages['index']['_id']
    expect(pages['about']['parent_ids']).to eq [pages['index']['_id']]
  end

  it 'writes the page body as a localized raw_template' do
    about = AdapterParityFixture.mongodb_client['locomotive_pages']
                                .find('_id' => AdapterParityFixture::MongoDBPages.page_id('about')).first

    expect(about['raw_template']['en'].strip).to eq 'About body en'
    expect(about['raw_template']['fr'].strip).to eq 'About body fr'
    expect(about['fullpath']).to eq('en' => 'about', 'fr' => 'a-propos')
  end

  it 'keeps the Wagon definition unchanged while compiling MongoDB documents' do
    expect(AdapterParityFixture::WagonSections.section('gallery')[:definition]['default'])
      .to eq('settings' => { 'columns' => 4, 'framed' => false })
  end

  it 'writes the section definition a push leaves behind' do
    gallery = AdapterParityFixture.mongodb_client['locomotive_sections']
                                  .find('site_id' => AdapterParityFixture::SITE_ID, 'slug' => 'gallery').first

    expect(gallery['name']).to eq 'Gallery'
    expect(gallery['template'].strip).to eq '<ul class="gallery"></ul>'
    expect(gallery['definition']['default'])
      .to eq('settings' => { 'columns' => 4, 'framed' => false, 'rows' => 2 })
  end

  it 'writes a snippet template per locale, with no key where there is no file' do
    snippets = AdapterParityFixture.mongodb_client['locomotive_snippets']
                                   .find('site_id' => AdapterParityFixture::SITE_ID).to_a
                                   .each_with_object({}) { |snippet, all| all[snippet['slug']] = snippet }

    expect(snippets['greeting']['name']).to eq 'Greeting'
    expect(snippets['greeting']['template']['fr'].strip).to eq 'Greeting fr'
    expect(snippets['banner']['template'].keys).to eq %w(en)
  end

  it 'writes a translation as its locale values, without Engine completion' do
    translations = AdapterParityFixture.mongodb_client['locomotive_translations']
                                       .find('site_id' => AdapterParityFixture::SITE_ID).to_a
                                       .each_with_object({}) { |row, all| all[row['key']] = row }

    expect(translations['powered_by']['values']).to eq('en' => 'Powered by', 'fr' => 'Propulsé par')
    expect(translations['adapter_parity_english_only']['values'].keys).to eq %w(en)
    expect(translations['adapter_parity_english_only']).not_to have_key('completion')
  end

  it 'writes a theme asset under the local path Engine looks it up by' do
    written = AdapterParityFixture.mongodb_client['locomotive_theme_assets']
                                  .find('site_id' => AdapterParityFixture::SITE_ID).to_a

    expect(written.map { |asset| asset['local_path'] }).to eq %w(stylesheets/parity.css)
    expect(written.first['folder']).to eq 'stylesheets'
    expect(written.first['checksum']).to eq Digest::MD5.hexdigest("body { color: #333; }\n")
  end

  it 'leaves a missing key out instead of writing a null' do
    expect(document('all-missing')).not_to have_key('score')
  end

  it 'writes an explicit null as a present null' do
    expect(document('explicit-nils')).to include('score' => nil)
  end

  it 'writes a select as its option id, not the option name' do
    expect(document('scalars')['category_id']).to be_a(BSON::ObjectId)
  end

  def specimens_field(name)
    AdapterParityFixture.mongodb_client['locomotive_content_types']
                        .find('site_id' => AdapterParityFixture::SITE_ID, 'slug' => 'specimens').first
                        .fetch('entries_custom_fields').detect { |field| field['name'] == name }
  end

  it 'writes a localized select as the same declared option id in each locale' do
    options = specimens_field('tier').fetch('select_options')

    expect(document('scalars')['tier_id']).to eq(
      'en' => options.first['_id'],
      'fr' => options.first['_id']
    )

    expect(document('arrays')['tier_id']).to eq(
      'en' => options.last['_id'],
      'fr' => options.last['_id']
    )
  end

  it 'writes a belongs_to as the target id, and leaves it out when unlinked' do
    expect(document('scalars')['maker_id']).to be_a(BSON::ObjectId)
    expect(document('zero')).not_to have_key('maker_id')
  end

  it 'writes a many_to_many as a list of target ids' do
    expect(document('scalars')['topic_ids']).to all(be_a(BSON::ObjectId))
  end

  it 'writes a date time as a Time, not the string the fixture holds' do
    expect(document('scalars')['at']).to be_a(Time)
  end

  it 'writes a date as UTC midnight' do
    expect(document('scalars')['held_on']).to eq Time.utc(2013, 2, 11)
  end

  it 'writes the label as a field, since only Wagon keeps it in the key' do
    expect(document('scalars')['name']).to eq 'Scalars'
  end

  it 'writes a localized value as a per-locale hash, missing locales absent' do
    expect(document('scalars')['title']).to eq('en' => 'Scalars en', 'fr' => 'Scalars fr')
    expect(document('arrays')['title']).to eq('en' => 'Arrays en')
    expect(document('embedded')['title']).to include('fr' => nil)
  end

  it 'keeps the key order of an embedded document' do
    expect(document('embedded')['payload'].keys).to eq %w(b a)
  end

end
