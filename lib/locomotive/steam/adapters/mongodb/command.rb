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

        def inc(entity, attribute, amount = 1)
          entity.tap do
            @collection.update_one(write_filter(entity), '$inc' => { attribute => amount })
            entity[attribute] ||= 0
            entity[attribute] += amount
          end
        end

        def delete(entity)
          @collection.delete_one(write_filter(entity))
        end

        private

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
