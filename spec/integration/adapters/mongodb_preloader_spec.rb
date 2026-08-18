require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'
require_relative '../../support/adapter_parity_fixture'

# Command ceilings for bounded preloaders on real MongoDB.
describe 'MongoDB window preloader cost' do

  SITE_ID         = BSON::ObjectId.from_string('bbbbbbbbbbbbbbbbbbbbbbbb')
  FOREIGN_SITE_ID = BSON::ObjectId.from_string('bbbbbbbbbbbbbbbbbbbbbbbe')
  TOPICS_ID  = BSON::ObjectId.from_string('bbbbbbbbbbbbbbbbbbbbbbb1')
  POSTS_ID   = BSON::ObjectId.from_string('bbbbbbbbbbbbbbbbbbbbbbb2')
  AUTHORS_ID = BSON::ObjectId.from_string('bbbbbbbbbbbbbbbbbbbbbbb3')
  OWNERS     = 20
  AUTHORS    = 5

  def self.field(position, name, type, extra = {})
    { '_id' => BSON::ObjectId.new, 'position' => position, 'name' => name, 'type' => type,
      'label' => name, 'required' => false, 'localized' => false, 'unique' => false }.merge(extra)
  end

  before(:all) do
    client = AdapterParityFixture.mongodb_client

    %w(locomotive_sites locomotive_content_types locomotive_content_entries).each do |collection|
      client[collection].delete_many({ 'site_id' => { '$in' => [SITE_ID, FOREIGN_SITE_ID] } })
    end
    client['locomotive_sites'].delete_many({ '_id' => SITE_ID })

    client['locomotive_sites'].insert_one(
      '_id' => SITE_ID, 'name' => 'Preloader probe', 'handle' => 'preloader-probe',
      'timezone_name' => 'UTC', 'locales' => %w(en), 'domains' => [])

    client['locomotive_content_types'].insert_one(
      '_id' => TOPICS_ID, 'site_id' => SITE_ID, 'name' => 'Probe topics', 'slug' => 'probe_topics',
      'label_field_name' => 'name', 'order_by' => 'manually', 'order_direction' => 'asc',
      'entries_custom_fields' => [self.class.field(0, 'name', 'string')])

    client['locomotive_content_types'].insert_one(
      '_id' => POSTS_ID, 'site_id' => SITE_ID, 'name' => 'Probe posts', 'slug' => 'probe_posts',
      'label_field_name' => 'title', 'order_by' => 'manually', 'order_direction' => 'asc',
      'entries_custom_fields' => [
        self.class.field(0, 'title', 'string'),
        self.class.field(1, 'topics', 'many_to_many',
                         'class_name' => "Locomotive::ContentEntry#{TOPICS_ID}"),
        self.class.field(2, 'author', 'belongs_to',
                         'class_name' => "Locomotive::ContentEntry#{AUTHORS_ID}")
      ])

    client['locomotive_content_types'].insert_one(
      '_id' => AUTHORS_ID, 'site_id' => SITE_ID, 'name' => 'Probe authors', 'slug' => 'probe_authors',
      'label_field_name' => 'name', 'order_by' => 'manually', 'order_direction' => 'asc',
      'entries_custom_fields' => [
        self.class.field(0, 'name', 'string'),
        self.class.field(1, 'posts', 'has_many',
                         'class_name' => "Locomotive::ContentEntry#{POSTS_ID}", 'inverse_of' => 'author')
      ])

    AUTHORS.times do |index|
      client['locomotive_content_entries'].insert_one(
        '_id' => author_id(index), 'site_id' => SITE_ID, 'content_type_id' => AUTHORS_ID,
        '_slug' => { 'en' => "author-#{index}" }, '_position' => index, '_visible' => true,
        'name' => "Author #{index}")
    end

    # Decoys naming a real author: a stranger tenant and a stranger type.
    client['locomotive_content_entries'].insert_one(
      '_id' => BSON::ObjectId.new, 'site_id' => FOREIGN_SITE_ID, 'content_type_id' => POSTS_ID,
      '_slug' => { 'en' => 'decoy-tenant' }, '_position' => 900, '_visible' => true,
      'title' => 'Decoy tenant', 'author_id' => author_id(0))
    client['locomotive_content_entries'].insert_one(
      '_id' => BSON::ObjectId.new, 'site_id' => SITE_ID, 'content_type_id' => TOPICS_ID,
      '_slug' => { 'en' => 'decoy-type' }, '_position' => 901, '_visible' => true,
      'name' => 'Decoy type', 'author_id' => author_id(0))

    shared_hidden = topic_id(:shared, 0)

    client['locomotive_content_entries'].insert_one(
      '_id' => shared_hidden, 'site_id' => SITE_ID, 'content_type_id' => TOPICS_ID,
      '_slug' => { 'en' => 'shared-hidden' }, '_position' => 90, '_visible' => false,
      'name' => 'Shared hidden')

    OWNERS.times do |index|
      client['locomotive_content_entries'].insert_one(
        '_id' => topic_id(:hidden, index), 'site_id' => SITE_ID, 'content_type_id' => TOPICS_ID,
        '_slug' => { 'en' => "hidden-#{index}" }, '_position' => 100 + index, '_visible' => false,
        'name' => "Hidden #{index}")
      client['locomotive_content_entries'].insert_one(
        '_id' => topic_id(:visible, index), 'site_id' => SITE_ID, 'content_type_id' => TOPICS_ID,
        '_slug' => { 'en' => "visible-#{index}" }, '_position' => 200 + index, '_visible' => true,
        'name' => "Visible #{index}")

      client['locomotive_content_entries'].insert_one(
        '_id' => BSON::ObjectId.new, 'site_id' => SITE_ID, 'content_type_id' => POSTS_ID,
        '_slug' => { 'en' => "unique-#{index}" }, '_position' => index, '_visible' => true,
        'title' => "Unique #{index}", 'author_id' => author_id(index % AUTHORS),
        'topic_ids' => [topic_id(:hidden, index), topic_id(:visible, index)])
      client['locomotive_content_entries'].insert_one(
        '_id' => BSON::ObjectId.new, 'site_id' => SITE_ID, 'content_type_id' => POSTS_ID,
        '_slug' => { 'en' => "shared-#{index}" }, '_position' => 100 + index, '_visible' => true,
        'title' => "Shared #{index}", 'topic_ids' => [shared_hidden, topic_id(:visible, index)])
    end
  end

  after(:all) do
    client = AdapterParityFixture.mongodb_client

    %w(locomotive_sites locomotive_content_types locomotive_content_entries).each do |collection|
      client[collection].delete_many({ 'site_id' => { '$in' => [SITE_ID, FOREIGN_SITE_ID] } })
    end
    client['locomotive_sites'].delete_many({ '_id' => SITE_ID })
  end

  def self.topic_id(kind, index)
    prefix = { shared: 'c', hidden: 'a', visible: 'b' }.fetch(kind)

    BSON::ObjectId.from_string("ddddddddddddddddddddd#{prefix}#{index.to_s(16).rjust(2, '0')}")
  end

  def topic_id(kind, index)
    self.class.topic_id(kind, index)
  end

  def self.author_id(index)
    BSON::ObjectId.from_string("ddddddddddddddddddddde#{index.to_s(16).rjust(2, '0')}")
  end

  def author_id(index)
    self.class.author_id(index)
  end

  class CommandCounter
    def commands = @commands ||= []

    def started(event)
      name = event.command_name
      return unless %w(find aggregate getMore).include?(name)

      commands << [name, event.command[name] || event.command['collection']]
    end
    def succeeded(_); end
    def failed(_); end
  end

  let(:adapter)         { AdapterParityFixture.mongodb_adapter }
  let(:site)            { Locomotive::Steam::SiteRepository.new(adapter).by_handle_or_domain('preloader-probe', nil) }
  let(:type_repository) { Locomotive::Steam::ContentTypeRepository.new(adapter, site, :en) }

  def counted_window_heads(slug_prefix)
    repository = Locomotive::Steam::ContentEntryRepository.new(adapter, site, :en, type_repository)
    window     = repository.with(type_repository.by_slug('probe_posts'))
                           .all('_slug.in' => OWNERS.times.map { |index| "#{slug_prefix}-#{index}" })

    Locomotive::Steam::Models::AssociationPreloader.attach(window)

    client  = Locomotive::Steam::MongoDBAdapter.session
    counter = CommandCounter.new
    client.subscribe(Mongo::Monitoring::COMMAND, counter)

    begin
      heads = window.map { |post| post.topics.load_window(nil, 0, 1).map(&:name) }
    ensure
      client.unsubscribe(Mongo::Monitoring::COMMAND, counter)
    end

    [heads, counter]
  end

  it 'answers twenty hidden-headed windows without growing per owner' do
    heads, counter = counted_window_heads('unique')

    expect(heads).to eq OWNERS.times.map { |index| ["Visible #{index}"] }
    expect(counter.commands.count(['find', 'locomotive_content_entries'])).to be <= 7
    expect(counter.commands.count(['find', 'locomotive_content_types'])).to eq 1
  end

  it 'reads the posts of every author through two entry finds and one bounded count' do
    repository = Locomotive::Steam::ContentEntryRepository.new(
      adapter, site, :en, type_repository)
    window = repository.with(type_repository.by_slug('probe_authors')).all

    Locomotive::Steam::Models::AssociationPreloader.attach(window)

    client  = Locomotive::Steam::MongoDBAdapter.session
    counter = CommandCounter.new
    client.subscribe(Mongo::Monitoring::COMMAND, counter)

    begin
      groups = window.map { |author| author.posts.all.map { |post| post._slug[:en] } }
    ensure
      client.unsubscribe(Mongo::Monitoring::COMMAND, counter)
    end

    expect(groups).to eq AUTHORS.times.map { |index|
      [index, index + 5, index + 10, index + 15].map { |i| "unique-#{i}" }
    }
    expect(counter.commands.count(['find', 'locomotive_content_entries'])).to eq 2
    expect(counter.commands.count(['find', 'locomotive_content_types'])).to eq 1
    expect(counter.commands.count(['aggregate', 'locomotive_content_entries'])).to eq 1
    expect(counter.commands.count { |name, _| name == 'getMore' }).to eq 0
  end

  it 'answers a shared hidden head from the negative cache' do
    heads, counter = counted_window_heads('shared')

    expect(heads).to eq OWNERS.times.map { |index| ["Visible #{index}"] }
    expect(counter.commands.count(['find', 'locomotive_content_entries'])).to be <= 4
  end

end
