# frozen_string_literal: true

require_relative 'operator'

module Locomotive::Steam
  module Adapters
    module Query

      # The closed registry of supported operators — the single source of truth
      # for what an operator means, shared by every engine. An operator absent
      # here is unsupported; there is no separate deny-list.
      module Operators

        ALL = [
          Operator.new(:eq,     '$eq',     :literal),
          Operator.new(:ne,     '$ne',     :literal),
          Operator.new(:gt,     '$gt',     :scalar),
          Operator.new(:gte,    '$gte',    :scalar),
          Operator.new(:lt,     '$lt',     :scalar),
          Operator.new(:lte,    '$lte',    :scalar),
          Operator.new(:in,     '$in',     :list),
          Operator.new(:nin,    '$nin',    :list),
          Operator.new(:all,    '$all',    :list),
          Operator.new(:size,   '$size',   :size),
          Operator.new(:exists, '$exists', :boolean),
        ].freeze

        BY_NAME = ALL.to_h { |operator| [operator.name.to_s, operator] }.freeze

        ALIASES = { '==' => 'eq' }.freeze

        # operators exposed to {% with_scope %} — no eq (plain equality carries
        # no suffix) and no aliases
        PUBLIC = %i(all exists gt gte in lt lte ne nin size).freeze

        module_function

        def fetch(operator)
          name = operator.to_s
          name = ALIASES.fetch(name, name)

          BY_NAME[name] ||
            raise(UnsupportedOperator, "unsupported operator: #{operator.inspect}")
        end

        def key(name, operator)
          "#{name}.#{fetch(operator).name}"
        end

      end

    end
  end
end
