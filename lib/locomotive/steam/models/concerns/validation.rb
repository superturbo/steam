require 'forwardable'

module Locomotive
  module Steam
    module Models
      module Concerns

        module Validation

          def errors
            @errors ||= Errors.new
          end

          def valid?
            true
          end

          class Errors

            include Enumerable
            extend Forwardable

            attr_accessor :messages
            attr_reader :codes

            def_delegators :@messages, :[], :empty?, :each, :size, :to_hash

            alias_method :blank?, :empty?

            def initialize
              @messages = HashWithIndifferentAccess.new({})
              @codes    = HashWithIndifferentAccess.new({})
            end

            def add(attribute, message, options = {})
              text = generate_message(message, options)

              (@codes[attribute]    ||= []) << (message.is_a?(Symbol) ? message : :invalid)
              (@messages[attribute] ||= []) << text
            end

            def clear
              @codes.clear
              @messages.clear
            end

            def generate_message(message, options = {})
              I18n.t(message, **{
                scope:    'errors.messages',
                default:  message
              }.merge(options))
            end

          end

        end

      end
    end
  end
end
