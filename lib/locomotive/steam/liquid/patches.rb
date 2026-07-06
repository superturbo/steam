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

  class PartialCache

    def self.load(template_name, context:, parse_context:)
      cached_partials = context.registers[:cached_partials]
      cache_key = "#{template_name}:#{parse_context.error_mode}"
      cached = cached_partials[cache_key]
      return cached if cached

      file_system = context.registers[:file_system]
      source      = file_system.read_template_file(template_name)

      parse_context.partial = true

      template = context.registers[:template_factory].for(template_name)

      begin
        partial = template.parse(source, parse_context)
      rescue Locomotive::Steam::TemplateError
        raise
      rescue ::Liquid::SyntaxError => e
        raise Locomotive::Steam::LiquidError.new(e, template_name, source)
      end

      partial.name ||= template_name
      cached_partials[cache_key] = partial
    ensure
      parse_context.partial = false
    end

  end
end
