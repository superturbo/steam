# Enhance the IF condition to write the following statement:
#
# {% if value is present %}Value is not blank{% endif %}
# {% if 'Hello world' starts_with 'Hello' %}Value starts with 'hello'{% endif %}
#
Liquid::Condition.operators['is'.freeze] = proc { |cond, left, right|  cond.send(:equal_variables, left, right) }
Liquid::Condition.operators['starts_with'.freeze] = proc { |_cond, left, right| left.present? && right.present? && left.starts_with?(right) }

module Liquid

  class Condition

    @@method_literals['present'.freeze] = MethodLiteral.new(:present?, '').freeze

  end

  class ParseContext

    def []=(option_key, value)
      @options[option_key] = value
    end

    def merge(options)
      @template_options.merge(options)
    end

  end
end
