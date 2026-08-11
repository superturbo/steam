require 'mongo'
require 'mongo/active_support'

require_relative 'query'
require_relative 'mongodb/query'
require_relative 'mongodb/dataset'
require_relative 'mongodb/command'

module Locomotive::Steam

  class MongoDBAdapter

    attr_accessor_initialize :options

    def all(mapper, query)
      dataset(mapper, query)
    end

    def query(mapper, scope, &block)
      query = query_klass.new(scope, mapper.localized_attributes, &block)
      all(mapper, query)
    end

    def count(mapper, scope, &block)
      query = query_klass.new(scope, mapper.localized_attributes, &block)
      query.against(collection(mapper)).count_documents
    end

    def find(mapper, scope, id)
      _id = make_id(id)
      query(mapper, scope) { where(_id: _id) }.first
    end

    def create(mapper, scope, entity)
      command(mapper, scope).insert(entity)
    end

    def update(mapper, scope, entity)
      command(mapper, scope).update(entity)
    end

    def inc(mapper, scope, entity, attribute, amount = 1)
      command(mapper, scope).inc(entity, attribute, amount)
    end

    def delete(mapper, scope, entity)
      command(mapper, scope).delete(entity)
    end

    def key(name, operator)
      Adapters::Query::Operators.key(name, operator)
    end

    def make_id(id)
      return id if id.is_a?(BSON::ObjectId)
      return false unless BSON::ObjectId.legal?(id)

      BSON::ObjectId.from_string(id)
    end

    def base_url(mapper, scope, entity = nil)
      return nil if scope.site.nil?

      # Note: mimic the Carrierwave behavior
      base = "/sites/#{scope.site._id.to_s}"

      case mapper.name
      when :theme_assets      then "#{base}/theme"
      when :pages             then "#{base}/pages/#{entity._id}/files"
      when :content_entries   then "#{base}/content_entry#{scope.context[:content_type]._id}/#{entity._id}/files"
      end
    end

    class << self

      attr_reader :session

      def build_session(uri_or_hosts, client_options)
        @session ||= Mongo::Client.new(uri_or_hosts, client_options).tap do |client|
          # Missing-record detection requires acknowledged write results; a
          # nil concern is the driver default, which acknowledges.
          if client.write_concern && !client.write_concern.acknowledged?
            client.close
            raise ArgumentError, 'the MongoDB adapter requires acknowledged writes; w: 0 is not supported'
          end
        end
      end

      def disconnect_session
        @session.try(:close).tap do
          @session = nil
        end
      end

    end

    private

    def query_klass
      Locomotive::Steam::Adapters::MongoDB::Query
    end

    def command_klass
      Locomotive::Steam::Adapters::MongoDB::Command
    end

    def dataset(mapper, query)
      Locomotive::Steam::Adapters::MongoDB::Dataset.new(query.against(collection(mapper)), mapper)
    end

    def command(mapper, scope)
      command_klass.new(collection(mapper), mapper, scope)
    end

    def collection(mapper)
      session["locomotive_#{mapper.name}"]
    end

    def session
      self.class.build_session(uri_or_hosts, client_options)
    end

    def uri_or_hosts
      options[:uri] || [*options[:hosts]]
    end

    def client_options
      options.slice(*Mongo::Client::VALID_OPTIONS)
    end

  end

end


