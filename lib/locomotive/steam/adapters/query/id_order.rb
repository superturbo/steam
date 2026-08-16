module Locomotive::Steam
  module Adapters
    module Query

      module IdOrder

        module_function

        # Each ID reads through the shared scalar grammar, so the reordering
        # index sees the same value the store filter matched.
        def normalize(ids)
          raise InvalidValue, 'in_id_order takes a list of IDs' unless ids.is_a?(::Array)

          ids.map { |id| Values.scalar(id) }
             .reject { |id| Values.unmatchable?(id) }
             .uniq
        end

      end

    end
  end
end
