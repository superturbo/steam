require 'set'

module Locomotive::Steam
  module Adapters
    module Query

      # Shared normalization and validation for neutral query criteria.
      module Criteria

        module_function

        # Stringify keys recursively and reject collisions.
        def normalize(criteria)
          return {} if criteria.nil?

          unless criteria.is_a?(Hash)
            raise InvalidValue, "expected criteria to be a Hash, got #{criteria.class}"
          end

          criteria.each_with_object({}) do |(key, value), memo|
            name = key.to_s

            raise InvalidValue, "duplicate query key: #{name.inspect}" if memo.key?(name)

            memo[name] = normalize_value(value)
          end
        end

        def normalize_value(value)
          case value
          when Hash       then normalize(value)
          when Array, Set then value.map { |element| normalize_value(element) }
          else value
          end
        end

        private_class_method :normalize_value

        # The security boundary of the neutral DSL: user criteria may never
        # smuggle a raw MongoDB operator, in a key or nested anywhere in a
        # value. Only keys are operators — a "$100" value is ordinary data. Both
        # engines run this, so Wagon cannot accept criteria Engine rejects.
        def reject_raw_operators!(criteria)
          criteria.each do |key, value|
            reject!('keys', key)
            reject_values!(value)
          end

          criteria
        end

        def reject_values!(value)
          case value
          when Hash
            value.each do |key, nested|
              reject!('values', key)
              reject_values!(nested)
            end
          when Array, Set
            value.each { |element| reject_values!(element) }
          end
        end

        def reject!(subject, name)
          return unless name.to_s.split('.').any? { |part| part.start_with?('$') }

          raise UnsupportedOperator, "#{subject} may not contain a Mongo operator: #{name.inspect}"
        end

        private_class_method :reject_values!, :reject!

      end

    end
  end
end
