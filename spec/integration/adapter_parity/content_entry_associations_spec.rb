require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'
require_relative '../../support/adapter_parity_fixture'
require_relative '../../support/adapter_parity_context'

describe 'Adapter parity' do

  shared_examples_for 'the adapter parity dataset' do

    include_context 'adapter parity dataset access'

    describe 'the content entry repository' do

      # Source states: missing, null, [], [nil], [id, nil], and linked ids.
      describe 'querying a many_to_many by nil' do

        # A lone nil reaches the operator layer untouched; the emptied list is
        # a value of its own, not a shade of nil.
        it 'matches a missing, null, or null-holding list through nil' do
          expect(slugs(topics: nil))
            .to match_array %w(all-missing arrays embedded explicit-nils)
        end

        it 'negates nil to the lists free of nulls' do
          expect(slugs('topics.ne' => nil)).to match_array %w(scalars zero)
        end

        it 'treats in nil as in [null]' do
          expect(slugs('topics.in' => nil))
            .to match_array %w(all-missing arrays embedded explicit-nils)
        end

        it 'treats nin nil as its complement' do
          expect(slugs('topics.nin' => nil)).to match_array %w(scalars zero)
        end

        it 'treats all nil as all [null]' do
          expect(slugs('topics.all' => nil))
            .to match_array %w(all-missing arrays embedded explicit-nils)
        end

        # Explicit lists keep exact-list equality.
        it 'matches the emptied list through an explicit empty list' do
          expect(slugs(topics: [])).to eq %w(zero)
        end

        it 'matches the null element through an explicit null list' do
          expect(slugs(topics: [nil])).to eq %w(embedded)
        end

        it 'matches the mixed list through the same explicit list' do
          expect(slugs(topics: ['topic-b', nil])).to eq %w(arrays)
        end

      end

      # An unresolved slug is not a missing association.
      describe 'querying an association by an unresolved slug' do

        it 'matches nothing through equality' do
          expect(slugs(maker: 'maker-nobody')).to eq []
        end

        it 'matches nothing through a blank slug' do
          expect(slugs(maker: '')).to eq []
        end

        it 'negates an unresolved slug to everything' do
          expect(slugs('maker.ne' => 'maker-nobody'))
            .to match_array %w(all-missing arrays embedded explicit-nils scalars zero)
        end

        it 'drops the unresolved element from in' do
          expect(slugs('maker.in' => %w(maker-one maker-nobody)))
            .to match_array %w(arrays scalars)
        end

        it 'drops the unresolved element from nin' do
          expect(slugs('maker.nin' => %w(maker-one maker-nobody)))
            .to match_array %w(all-missing embedded explicit-nils zero)
        end

        it 'matches nothing through all with an unresolved element' do
          expect(slugs('topics.all' => %w(topic-a topic-nobody))).to eq []
        end

      end

      describe 'querying association operands by form' do

        def quoted(conditions)
          repository = Locomotive::Steam::ContentEntryRepository.new(
            adapter, site, AdapterParityFixture::LOCALE, type_repository)

          repository.with(type_repository.by_slug('quoted')).all(conditions).map do |entry|
            entry._slug[AdapterParityFixture::LOCALE]
          end
        end

        it 'reads a 24-hex string as a slug, never as an id' do
          expect(quoted(maker: '0123456789abcdef01234567')).to eq %w(spelled)
        end

        it 'finds the linked entries through the target entry' do
          expect(slugs(maker: makers.by_slug('maker-one')))
            .to match_array %w(arrays scalars)
        end

        it 'finds them through the id the store issued' do
          expect(slugs(maker: makers.by_slug('maker-one')._id))
            .to match_array %w(arrays scalars)
        end

        it 'finds them through a hash naming a stringified id' do
          expect(slugs(maker: { _id: makers.by_slug('maker-one')._id.to_s }))
            .to match_array %w(arrays scalars)
        end

        it 'matches nothing through an id no store issued' do
          expect(slugs(maker: { _id: 'ffffffffffffffffffffffff' })).to eq []
        end

        it 'matches nothing through a hash naming no id' do
          expect(slugs(maker: { _id: nil })).to eq []
        end

        it 'reads a symbol as the slug it spells' do
          expect(slugs(maker: :'maker-one')).to match_array %w(arrays scalars)
        end

        it 'matches nothing through an entry the store never persisted' do
          expect(slugs(maker: makers.build(name: 'Ghost'))).to eq []
        end

      end

      describe 'reading a many_to_many in the owner sequence' do

        def playlist(slug)
          repository = Locomotive::Steam::ContentEntryRepository.new(
            adapter, site, AdapterParityFixture::LOCALE, type_repository)

          repository.with(type_repository.by_slug('playlists')).all.detect do |candidate|
            candidate._slug[AdapterParityFixture::LOCALE] == slug
          end
        end

        it 'reads it even against the target order' do
          topics = playlist('reversed').topics

          expect(topics.all.map { |topic| topic._slug[AdapterParityFixture::LOCALE] })
            .to eq %w(topic-b topic-a)
          expect(topics.first._slug[AdapterParityFixture::LOCALE]).to eq 'topic-b'
        end

      end

      describe 'reading has_many through a window preloader' do

        it 'resolves the same groups in the same orders' do
          repository = Locomotive::Steam::ContentEntryRepository.new(
            adapter, site, AdapterParityFixture::LOCALE, type_repository)
          window = repository.with(type_repository.by_slug('makers')).all

          Locomotive::Steam::Models::AssociationPreloader.attach(window)

          specimens = window.to_h do |maker|
            [maker._slug[AdapterParityFixture::LOCALE],
             maker.specimens.all.map { |specimen| specimen._slug[AdapterParityFixture::LOCALE] }]
          end

          expect(specimens).to eq(
            'maker-one'                => %w(scalars arrays),
            'maker-two'                => %w(embedded),
            'maker-three'              => [],
            '0123456789abcdef01234567' => [])
        end

        it 'keeps an explicit position order through the batch' do
          repository = Locomotive::Steam::ContentEntryRepository.new(
            adapter, site, AdapterParityFixture::LOCALE, type_repository)
          window = repository.with(type_repository.by_slug('makers')).all

          Locomotive::Steam::Models::AssociationPreloader.attach(window)

          badges = window.to_h do |maker|
            [maker._slug[AdapterParityFixture::LOCALE],
             maker.badges.all.map { |badge| badge._slug[AdapterParityFixture::LOCALE] }]
          end

          expect(badges).to eq(
            '0123456789abcdef01234567' => [],
            'maker-one'                => %w(gold silver bronze),
            'maker-three'              => [],
            'maker-two'                => [])
        end

      end

      describe 'reading belongs_to through a window preloader' do

        def specimen_window
          repository = Locomotive::Steam::ContentEntryRepository.new(
            adapter, site, AdapterParityFixture::LOCALE, type_repository)

          repository.with(type_repository.by_slug('specimens')).all
        end

        it 'resolves the same targets as one-by-one reads' do
          window = specimen_window
          Locomotive::Steam::Models::AssociationPreloader.attach(window)

          expect(window.map { |entry| entry.maker&.name })
            .to eq [nil, 'Maker one', 'Maker two', nil, 'Maker one', nil]
          expect(specimen_window.map { |entry| entry.maker&.name })
            .to eq [nil, 'Maker one', 'Maker two', nil, 'Maker one', nil]
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

    describe 'the physical cost of a preloaded window' do

      let(:adapter) { AdapterParityFixture.mongodb_adapter }

      include_context 'adapter parity dataset access'

      class FindCounter
        def finds = @finds ||= []

        def started(event)
          finds << event.command['find'] if event.command_name == 'find'
        end
        def succeeded(_); end
        def failed(_); end
      end

      it 'reads the topics of every playlist through two content-entry find commands' do
        repository = Locomotive::Steam::ContentEntryRepository.new(
          adapter, site, AdapterParityFixture::LOCALE, type_repository)
        window = repository.with(type_repository.by_slug('playlists')).all
        Locomotive::Steam::Models::AssociationPreloader.attach(window)

        # The adapter session predates any global subscription.
        client  = Locomotive::Steam::MongoDBAdapter.session
        counter = FindCounter.new
        client.subscribe(Mongo::Monitoring::COMMAND, counter)

        begin
          lists = window.map { |playlist| playlist.topics.all.map { |topic| topic._slug[AdapterParityFixture::LOCALE] } }
        ensure
          client.unsubscribe(Mongo::Monitoring::COMMAND, counter)
        end

        expect(lists).to eq [%w(topic-a), %w(topic-b), %w(topic-b topic-a), %w(topic-a)]
        expect(counter.finds.count('locomotive_content_entries')).to eq 2
      end

      it 'reads the heads of every playlist through two content-entry find commands' do
        repository = Locomotive::Steam::ContentEntryRepository.new(
          adapter, site, AdapterParityFixture::LOCALE, type_repository)
        window = repository.with(type_repository.by_slug('playlists')).all
        Locomotive::Steam::Models::AssociationPreloader.attach(window)

        client  = Locomotive::Steam::MongoDBAdapter.session
        counter = FindCounter.new
        client.subscribe(Mongo::Monitoring::COMMAND, counter)

        begin
          heads = window.map { |playlist| playlist.topics.load_window(nil, 0, 1).map { |topic| topic._slug[AdapterParityFixture::LOCALE] } }
        ensure
          client.unsubscribe(Mongo::Monitoring::COMMAND, counter)
        end

        expect(heads).to eq [%w(topic-a), %w(topic-b), %w(topic-b), %w(topic-a)]
        expect(counter.finds.count('locomotive_content_entries')).to eq 2
      end

    end

  end

  context 'Filesystem' do

    it_should_behave_like 'the adapter parity dataset' do
      let(:adapter) { AdapterParityFixture.filesystem_adapter }

      def filesystem?; true; end
    end

  end

end
