module Locomotive::Steam
  module Adapters

    # Shared query-layer primitives so a query means the same thing on every
    # storage engine — MongoDB (Engine) and Memory (Wagon).
    # See docs/query_semantics.md.
    module Query

      class InvalidValue < StandardError; end
      class UnsupportedOperator < StandardError; end

      # Returns UTF-8 query text, or nil when it cannot be transcoded.
      module Text

        module_function

        def utf8(value)
          return nil unless value.valid_encoding?

          value.encode(Encoding::UTF_8)
        rescue EncodingError
          nil
        end

      end

    end
  end
end

require_relative 'query/comparison'
require_relative 'query/values'
require_relative 'query/operators'
require_relative 'query/criteria'
require_relative 'query/order_by'
require_relative 'query/window'
