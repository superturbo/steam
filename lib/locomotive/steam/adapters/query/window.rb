module Locomotive::Steam
  module Adapters
    module Query

      module Window

        MAX = 2**63 - 1

        private_constant :MAX

        module_function

        # Clamp computed windows; direct query input remains strict.
        def clamp(value)
          value.clamp(0, MAX)
        end

        def normalize(value, name)
          return nil if value.nil?
          return value if value.is_a?(Integer) && value.between?(0, MAX)

          raise InvalidValue,
                "#{name} takes an integer between 0 and #{MAX}, got #{value.inspect}"
        end

      end

    end
  end
end
