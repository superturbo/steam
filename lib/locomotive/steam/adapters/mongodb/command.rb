require_relative '../numeric_bounds'
require_relative '../time_precision'

module Locomotive::Steam
  module Adapters
    module MongoDB

      class Command

        def initialize(collection, mapper, scope)
          @collection = collection
          @mapper     = mapper
          @scope      = scope
        end

        def insert(entity)
          # make sure the entity gets a valid id
          entity[:_id] ||= BSON::ObjectId.new

          serialized_entity = @mapper.serialize(entity)

          @collection.insert_one(serialized_entity)

          entity
        end

        def update(entity)
          entity.tap do
            @collection.update_one(write_filter(entity), '$set' => @mapper.serialize(entity))
          end
        end

        # Guard the stored type and remaining range in the atomic update filter.
        def inc(entity, attribute, amount = 1)
          now = Adapters::TimePrecision.utc_ms

          document = @collection.find_one_and_update(
            increment_filter(entity, attribute, amount),
            { '$inc' => { attribute => amount }, '$set' => { 'updated_at' => now } },
            return_document: :after, projection: { attribute => 1 })

          if document
            return entity.tap do
              entity[attribute]   = document[attribute]
              entity[:updated_at] = now
            end
          end

          refuse_increment!(entity, attribute, amount)
        end

        def delete(entity)
          @collection.delete_one(write_filter(entity))
        end

        private

        INCREMENT_TYPES = { Integer => %w(int long), Float => %w(double) }.freeze

        private_constant :INCREMENT_TYPES

        def increment_filter(entity, attribute, amount)
          low, high = Locomotive::Steam::Adapters::NumericBounds.room_for(amount)

          write_filter(entity).merge(
            '$or' => [
              { attribute => { '$exists' => false } },
              { attribute => { '$type' => INCREMENT_TYPES.fetch(amount.class),
                               '$gte' => low, '$lte' => high } }
            ]
          )
        end

        # Nothing was written: either the entry is gone or it holds a value the
        # increment cannot reach.
        def refuse_increment!(entity, attribute, amount)
          unless @collection.find(write_filter(entity), projection: { _id: 1 }).limit(1).first
            raise Locomotive::Steam::Models::Repository::RecordNotFound,
                  "could not find #{@collection.name} with _id = #{entity._id}"
          end

          raise Locomotive::Steam::InvalidIncrement,
                "#{attribute} cannot be incremented by #{amount.inspect}"
        end

        # Keep writes within the current site.
        def write_filter(entity)
          { _id: entity._id }.tap do |filter|
            filter[:site_id] = @scope.site._id if @scope.site
          end
        end

      end

    end
  end
end
