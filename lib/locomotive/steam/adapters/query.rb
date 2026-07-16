module Locomotive::Steam
  module Adapters

    # Shared query-layer primitives so a query means the same thing on every
    # storage engine — MongoDB (Engine) and Memory (Wagon). See
    # docs/query_semantics.md for the contract.
    module Query

      class InvalidValue < StandardError; end

    end
  end
end

require_relative 'query/values'
