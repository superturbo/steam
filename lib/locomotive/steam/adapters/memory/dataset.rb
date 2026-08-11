module Locomotive::Steam
  module Adapters
    module Memory

      class Dataset

        class InvalidIdentity < StandardError; end

        class PrimaryKey
          def initialize
            @current = 0
          end

          def increment!
            yield(@current += 1)
            @current
          end
        end

        attr_reader :records, :name

        def initialize(name)
          @name = name
          clear!
        end

        # Stored records are isolated from their callers.
        def insert(record)
          @primary_key.increment! do |id|
            _id = record[identity] || id
            raise InvalidIdentity, "#{name} already has #{identity} #{_id.inspect}" if records.key?(_id)

            record[identity] = _id
            records[_id] = copy_of(record)
          end
        end

        def update(record)
          id = record[identity]
          find(id)
          records[id] = copy_of(record)
          record
        end

        def delete(id)
          records.delete(id) { find(id) }
        end

        def reindex!
          @records = records.values.each_with_object({}) do |record, indexed|
            id = record[identity]
            raise InvalidIdentity, "#{name} has a record without an #{identity}" if id.nil?
            raise InvalidIdentity, "#{name} has a duplicate #{identity} #{id.inspect}" if indexed.key?(id)

            indexed[id] = record
          end
        end

        def size
          records.size
        end

        def all
          records.values
        end

        def find(id)
          records.fetch(id) do
            raise Locomotive::Steam::Models::Repository::RecordNotFound, "could not find #{name} with #{identity} = #{id}"
          end
        end

        def exists?(id)
          !!id && records.has_key?(id)
        end

        def query(locale = nil, &block)
          Query.new(self, locale, &block)
        end

        def clear!
          @records = {}
          @primary_key = PrimaryKey.new
        end

        private

        def identity
          @identity ||= :_id
        end

        def copy_of(record)
          record.is_a?(::Hash) ? Locomotive::Steam::Models::Copy.of(record) : record.dup
        end
      end
    end
  end
end
