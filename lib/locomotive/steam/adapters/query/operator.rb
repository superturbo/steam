module Locomotive::Steam
  module Adapters
    module Query

      # One operator described as data: its neutral name, the MongoDB operator
      # it maps to, and the value kind its argument is validated against. The
      # matching behaviour lives in the engines — this only describes it.
      Operator = Data.define(:name, :mongo_operator, :value_kind)

    end
  end
end
