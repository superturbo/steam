require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'
require_relative '../../support/adapter_parity_fixture'
require_relative '../../support/adapter_parity_context'

describe 'Adapter parity' do

  shared_examples_for 'the adapter parity dataset' do

    include_context 'adapter parity dataset access'

    describe 'the content entry repository' do

      it 'walks to the neighbours of an entry in that order' do
        embedded = specimens.by_slug('embedded')

        expect(specimens.next(embedded).name).to eq 'Explicit nils'
        expect(specimens.previous(embedded).name).to eq 'Arrays'
      end

      # Prologue and Epilogue have no part at all, Middle and Opening share
      # one, and en and fr disagree about where Finale sits.
      describe 'navigating a key with ties and nulls' do

        def entries_of(slug, locale = AdapterParityFixture::LOCALE)
          types = Locomotive::Steam::ContentTypeRepository.new(adapter, site, locale)

          Locomotive::Steam::ContentEntryRepository.new(adapter, site, locale, types)
            .with(types.by_slug(slug))
        end

        def order_of(slug, locale = AdapterParityFixture::LOCALE)
          entries_of(slug, locale).all.map { |entry| entry._slug[locale] }
        end

        def walk(step, slug, locale)
          repository = entries_of(slug, locale)

          order_of(slug, locale).map do |current|
            neighbour = repository.public_send(step, repository.by_slug(current))

            neighbour && neighbour._slug[locale]
          end
        end

        it 'reads nulls first, then the key, then the position' do
          expect(order_of('chapters')).to eq %w(prologue epilogue finale middle opening)
          expect(order_of('chapters', :fr)).to eq %w(prologue epilogue middle finale opening)
          expect(order_of('reverse_chapters')).to eq %w(opening middle finale epilogue prologue)
          expect(order_of('reverse_chapters', :fr)).to eq %w(opening finale middle epilogue prologue)
        end

        it 'steps through that order one entry at a time' do
          [['chapters', :en], ['chapters', :fr],
           ['reverse_chapters', :en], ['reverse_chapters', :fr]].each do |slug, locale|
            order = order_of(slug, locale)

            expect(walk(:next, slug, locale)).to eq [*order.drop(1), nil]
            expect(walk(:previous, slug, locale)).to eq [nil, *order[0..-2]]
          end
        end

        # A slug-ordered type needs no separate tie-breaker.
        it 'navigates a type ordered by the slug itself' do
          topics = entries_of('topics')

          expect(topics.next(topics.by_slug('topic-a'))._slug[:en]).to eq 'topic-b'
          expect(topics.previous(topics.by_slug('topic-b'))._slug[:en]).to eq 'topic-a'
          expect(topics.next(topics.by_slug('topic-b'))).to be_nil
        end

      end

    end

  end

  context 'MongoDB' do

    before(:all) { AdapterParityFixture.seed_mongodb! }
    after(:all)  { AdapterParityFixture.cleanup! }

    it_should_behave_like 'the adapter parity dataset' do
      let(:adapter)  { AdapterParityFixture.mongodb_adapter }

      def filesystem?; false; end
    end

  end

  context 'Filesystem' do

    it_should_behave_like 'the adapter parity dataset' do
      let(:adapter) { AdapterParityFixture.filesystem_adapter }

      def filesystem?; true; end
    end

  end

end
