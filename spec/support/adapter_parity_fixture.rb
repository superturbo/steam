require_relative 'adapter_parity_fixture/wagon_site'
require_relative 'adapter_parity_fixture/mongo_db_documents'

# Builds both adapter datasets from the same Wagon fixture. See the fixture's
# README for what belongs in it.
module AdapterParityFixture

  SITE_ID = WagonSite.site_id
  LOCALES = WagonSite.locales
  LOCALE  = WagonSite.default_locale

  # MongoDBAdapter reuses its first client process-wide, so integration fixtures
  # must share one database until the client becomes injectable.
  DATABASE = 'steam_test_1_8_x'
  HOSTS    = ['127.0.0.1:27017']

  module_function

  def mongodb_adapter
    Locomotive::Steam::MongoDBAdapter.new(database: DATABASE, hosts: HOSTS)
  end

  # Isolate filesystem state while keeping writes visible within one adapter.
  def filesystem_adapter
    Locomotive::Steam::FilesystemAdapter.new(WagonSite::PATH).tap do |adapter|
      adapter.cache = InstanceCacheStore.new
    end
  end

  def mongodb_client
    @mongodb_client ||= Mongo::Client.new(HOSTS, database: DATABASE)
  end

  # Compile before deleting: a broken fixture must not leave the database empty.
  def seed_mongodb!(client = mongodb_client)
    documents = MongoDBDocuments.documents

    clean_mongodb!(client)

    begin
      documents.each { |collection, rows| client[collection].insert_many(rows) if rows.any? }
    rescue StandardError
      clean_mongodb!(client)
      raise
    end
  end

  def clean_mongodb!(client = mongodb_client)
    client[MongoDBDocuments::SITES_COLLECTION].delete_many('_id' => SITE_ID)

    (MongoDBDocuments::COLLECTIONS - [MongoDBDocuments::SITES_COLLECTION]).each do |collection|
      client[collection].delete_many('site_id' => SITE_ID)
    end
  end

  # Close only the Mongo client owned by this fixture.
  def cleanup!
    clean_mongodb!

    @mongodb_client&.close
    @mongodb_client = nil
  end

end
