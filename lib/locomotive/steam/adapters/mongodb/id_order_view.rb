module Locomotive::Steam
  module Adapters
    module MongoDB

      # Lazily applies an ID sequence and its window to a MongoDB result.
      class IdOrderView

        include Enumerable

        def initialize(collection, filter, options, ids:, skip: nil, limit: nil)
          @collection, @filter, @options = collection, filter, options
          @ids, @skip, @limit = ids, skip, limit
        end

        # A new limit only narrows the window it finds.
        def limit(value)
          narrowed = @limit.nil? ? value : [@limit, value].min

          self.class.new(@collection, @filter, @options, ids: @ids, skip: @skip, limit: narrowed)
        end

        def each(&block)
          return enum_for(:each) unless block_given?

          documents.each(&block)

          self
        end

        # Counting ignores order but respects the window.
        def count_documents
          return 0 if @limit == 0 || @ids.empty?

          remaining = [@collection.count_documents(@filter) - (@skip || 0), 0].max

          @limit ? [remaining, @limit].min : remaining
        end

        private

        def documents
          @documents ||=
            if @limit == 0 || @ids.empty?
              []
            elsif @limit.nil? && (@skip || 0) == 0
              ordered_documents
            else
              windowed_documents
            end
        end

        def ordered_documents
          index = index_by_id(@collection.find(@filter, @options))

          @ids.filter_map { |id| index[id] }
        end

        def windowed_documents
          candidates           = matching_ids
          offset               = @skip || 0
          window               = candidates[offset, @limit || candidates.length] || []
          remaining_candidates = candidates.drop(offset + window.length)
          selected_documents   = fetch_documents(window)

          # A document gone between the phases yields its place to the next
          # candidate.
          while selected_documents.length < window.length && remaining_candidates.any?
            selected_documents += fetch_documents(remaining_candidates.shift(window.length - selected_documents.length))
          end

          selected_documents
        end

        # The first phase applies the whole filter, not mere existence.
        def matching_ids
          matching = index_by_id(@collection.find(@filter, projection: { '_id' => 1 }))

          @ids.select { |id| matching.key?(id) }
        end

        # The filter is repeated so a document no longer matching it cannot
        # come back through the window.
        def fetch_documents(ids)
          return [] if ids.empty?

          filter = { '$and' => [@filter, { '_id' => { '$in' => ids } }] }
          index  = index_by_id(@collection.find(filter, @options))

          ids.filter_map { |id| index[id] }
        end

        def index_by_id(documents)
          documents.each_with_object({}) { |document, index| index[document['_id']] = document }
        end

      end

    end
  end
end
