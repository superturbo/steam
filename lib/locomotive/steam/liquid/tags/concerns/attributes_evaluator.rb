module Locomotive
  module Steam
    module Liquid
      module Tags
        module Concerns

          # Evaluates the attributes parsed the AttributesParser
          module AttributesEvaluator
            extend ActiveSupport::Concern

            protected

            # The tag is parsed once and rendered many times, so a render reads
            # its own criteria rather than storing them on the tag.
            def evaluate_attributes(context)
              criteria = attributes_var_name.present? ? context[attributes_var_name] || {} : attributes

              unless criteria.is_a?(Hash)
                raise ::Liquid::SyntaxError,
                      "Invalid with_scope criteria: expected a hash, got #{criteria.class}"
              end

              evaluated = evaluate_hash(context, criteria) do |key|
                name = key.to_s
                # _slug instead of _permalink
                name = '_slug' if name == '_permalink'

                validate_criterion!(name)

                name
              end

              as_syntax_error { Locomotive::Steam::Adapters::Query::Criteria.reject_raw_operators!(evaluated) }
            end

            # A criterion means the same whether it was written in the markup or
            # handed over at render time, so a mistake in either reads the same.
            def validate_criterion!(key)
              operator = as_syntax_error do
                Locomotive::Steam::Adapters::Query::Operators.decode(key).last
              end

              return if operator.nil? ||
                        Locomotive::Steam::Adapters::Query::Operators::PUBLIC.include?(operator.name)

              raise ::Liquid::SyntaxError,
                    "Invalid with_scope criterion: #{key} is not an operator you can use here"
            end

            def as_syntax_error
              yield
            rescue Locomotive::Steam::Adapters::Query::InvalidValue,
                   Locomotive::Steam::Adapters::Query::UnsupportedOperator => e
              raise ::Liquid::SyntaxError, "Invalid with_scope criterion: #{e.message}"
            end

            def evaluate_hash(context, hash)
              hash.each_with_object({}) do |(key, value), memo|
                name = yield(key)

                raise ::Liquid::SyntaxError, "Duplicate with_scope key: #{name}" if memo.key?(name)

                memo[name] = evaluate_attribute(context, value)
              end
            end

            def evaluate_attribute(context, value)
              case value
              when Array 
                value.map { |v| evaluate_attribute(context, v) }
              when Hash
                evaluate_hash(context, value, &:to_s)
              when ::Liquid::VariableLookup
                evaluated_value = context.evaluate(value)
                evaluated_value.respond_to?(:_id) ? evaluated_value.send(:_source) : evaluate_attribute(context, evaluated_value)
              when Locomotive::Steam::Liquid::ContentTypeFieldSelectOption
                # Select scopes use option names.
                value.name
              else
                value
              end
            end
          end
        end
      end
    end
  end
end
