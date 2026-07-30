require 'set'

module Locomotive::Steam
  module Adapters
    module Query

      # The security boundary of the neutral DSL: user criteria may never smuggle
      # a raw MongoDB operator, in a key or nested anywhere in a value. Only keys
      # are operators — a "$100" value is ordinary data. Both engines run this,
      # so Wagon cannot accept criteria Engine rejects.
      module Criteria

        module_function

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
