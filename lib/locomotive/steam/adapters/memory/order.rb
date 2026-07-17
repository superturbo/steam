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
            value = entry.send(name)
            value = value[locale] if value.respond_to?(:translations)

            direction == :desc ? Desc.new(value) : Asc.new(value)
          end
        end

        class Direction
          attr_reader :obj
          def initialize(obj); @obj = obj; end
        end

        class Asc < Direction
          def <=>(other) @obj && other.obj ? @obj <=> other.obj : @obj ? -1 : 1; end
        end

        class Desc < Direction
          def <=>(other); @obj && other.obj ? other.obj <=> @obj : @obj ? -1 : 1; end
        end

      end

    end
  end
end
