require 'forwardable'

module Locomotive::Steam
  module Adapters
    module Memory

      class Query

        include Enumerable
        extend  Forwardable

        def_delegators :all, :each, :last, :to_s, :to_a, :empty?, :size

        alias :length :size
        alias :count :size

        attr_reader :conditions

        def initialize(dataset, locale = nil, &block)
          @dataset    = dataset
          @conditions = []
          @sorting    = nil
          @limit      = nil
          @offset     = 0
          @locale     = locale
          instance_eval(&block) if block_given?
        end

        def where(conditions = {})
          Adapters::Query::Criteria.reject_raw_operators!(conditions)

          @conditions += conditions.map { |name, value| Condition.new(name, value, @locale) }
          self
        end

        def +(query)
          @conditions += query.conditions
          self
        end

        def order_by(*args)
          @sorting = Order.new(*args)
          self
        end

        def limit(num)
          @limit = Adapters::Query::Window.normalize(num, :limit)
          self
        end

        def offset(num)
          @offset = Adapters::Query::Window.normalize(num, :offset)
          self
        end

        def only(*fields)
          self
        end

        def ==(other)
          if other.kind_of? Array
            all == other
          else
            super
          end
        end

        def all
          return [] if @limit == 0

          limited sorted(filtered)
        end

        def sorted(entries)
          return entries if @sorting.blank?

          entries.sort_by { |entry| @sorting.apply_to(entry, @locale) }
        end

        def limited(entries)
          return entries if @offset == 0 && @limit.nil?

          subentries = entries.drop(@offset || 0)

          @limit.nil? ? subentries : subentries.take(@limit)
        end

        def filtered
          @dataset.all.dup.find_all do |entry|
            accepted = true

            @conditions.each do |_condition|
              unless _condition.matches?(entry)
                accepted = false
                break # no to go further
              end
            end

            accepted
          end
        end # filtered

        def self.key(name, operator)
          Adapters::Query::Operators.key(name, operator)
        end

        def key(name, operator)
          self.class.key(name, operator)
        end

        alias :k :key

      end
    end
  end
end
