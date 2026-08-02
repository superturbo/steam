module Locomotive::Steam
  module Adapters

    # Shared query-layer primitives so a query means the same thing on every
    # storage engine — MongoDB (Engine) and Memory (Wagon).
    # See docs/query_semantics.md.
    module Query

      class InvalidValue < StandardError; end
      class UnsupportedOperator < StandardError; end

    end
  end
end

require_relative 'query/comparison'
require_relative 'query/values'
require_relative 'query/operators'
require_relative 'query/criteria'
require_relative 'query/order_by'
require_relative 'query/window'
