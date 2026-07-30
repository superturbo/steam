require_relative '../query'

module Locomotive::Steam
  module Adapters
    module Memory

      class Order

        attr_reader :list

        def initialize(*spec)
          @list = Adapters::Query::OrderBy.decode(*spec)
        end

        def empty?
          @list.empty?
        end

        def apply_to(entry, locale)
          @list.collect do |(name, direction)|
            value = read(entry, name)
            value = value[locale] if value.respond_to?(:translations)

            direction == :desc ? Desc.new(value) : Asc.new(value)
          end
        end

        protected

        # A field the entity does not carry sorts as null, the way MongoDB
        # reads a missing key, rather than raising mid-render.
        def read(entry, name)
          entry.respond_to?(name) ? entry.public_send(name) : nil
        end

        class Direction

          BOOLEANS = { false => 0, true => 1 }.freeze

          attr_reader :obj

          def initialize(obj); @obj = obj; end

          protected

          # Incomparable values must stay incomparable; treating them as equal breaks transitivity.
          def compare(one, other)
            return 0  if one.nil? && other.nil?
            return -1 if one.nil?
            return 1  if other.nil?
            return BOOLEANS[one] <=> BOOLEANS[other] if BOOLEANS.key?(one) && BOOLEANS.key?(other)

            one <=> other
          end

        end

        class Asc < Direction
          def <=>(other); compare(@obj, other.obj); end
        end

        class Desc < Direction
          def <=>(other); compare(other.obj, @obj); end
        end

      end

    end
  end
end
