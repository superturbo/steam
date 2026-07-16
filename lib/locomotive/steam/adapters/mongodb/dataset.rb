module Locomotive::Steam
  module Adapters
    module MongoDB

      # Reads from Mongo only when results are consumed.
      class Dataset < SimpleDelegator

        def initialize(view, mapper)
          @view, @mapper = view, mapper
          super(nil)
        end

        def each(&block)
          return enum_for(:each) unless block_given?

          if @records
            @records.each(&block)
          else
            @view.each { |attributes| yield entity(attributes) }
          end

          self
        end

        def first(*args)
          return @records.first(*args) if @records

          args.empty? ? entity(@view.limit(1).first) : __getobj__.first(*args)
        end

        def count(*args, &block)
          return @records.count(*args, &block) if @records

          args.empty? && block.nil? ? @view.count_documents : __getobj__.count(*args, &block)
        end

        def size
          @records ? @records.size : @view.count_documents
        end
        alias :length :size

        def empty?
          return @records.empty? if @records

          @view.limit(1).first.nil?
        end

        def all
          __getobj__
        end

        def __getobj__
          @records ||= @view.map { |attributes| entity(attributes) }
        end

        private

        def entity(attributes)
          @mapper.to_entity(attributes) if attributes
        end

      end

    end
  end
end
