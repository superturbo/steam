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

        it 'refuses an explicit list as an equality operand' do
          [[], [nil], ['topic-b', nil]].each do |list|
            expect { slugs(topics: list) }
              .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
          end
        end

        it 'reads the emptied list through its size' do
          expect(slugs('topics.size' => 0)).to eq %w(zero)
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

      describe 'resolving a slug operand across a write' do

        let(:render_repository) do
          Locomotive::Steam::ContentEntryRepository.new(
            adapter, site, AdapterParityFixture::LOCALE, type_repository)
        end

        let(:written) { [] }

        after do
          written.reverse_each do |type_slug, entry|
            render_repository.with(type_repository.by_slug(type_slug)).delete(entry)
          end
        end

        def create_in(type_slug, attributes)
          slug   = attributes.delete(:slug)
          scoped = render_repository.with(type_repository.by_slug(type_slug))
          entry  = scoped.build(attributes)

          entry[:_slug] = Locomotive::Steam::Models::I18nField.new(
            :_slug, AdapterParityFixture::LOCALE => slug)

          scoped.create(entry).tap { written << [type_slug, entry] }
        end

        def late_specimens
          render_repository.with(type_repository.by_slug('specimens'))
                           .all(topics: 'topic-late')
                           .map { |entry| entry._slug[AdapterParityFixture::LOCALE] }
        end

        it 'answers with the topic written after a missed resolution' do
          expect(late_specimens).to eq []

          topic = create_in('topics', name: 'Topic late', slug: 'topic-late')
          create_in('specimens', name: 'Late', score: 1, topic_ids: [topic._id],
                                 category_id: option_id(:category, 'alpha'),
                                 slug: 'late-specimen')

          expect(late_specimens).to eq %w(late-specimen)
        end

        it 'stops answering with a slug an update moved away' do
          topic = create_in('topics', name: 'Topic late', slug: 'topic-late')
          create_in('specimens', name: 'Late', score: 1, topic_ids: [topic._id],
                                 category_id: option_id(:category, 'alpha'),
                                 slug: 'late-specimen')

          expect(late_specimens).to eq %w(late-specimen)

          topic[:_slug] = Locomotive::Steam::Models::I18nField.new(
            :_slug, AdapterParityFixture::LOCALE => 'topic-moved')
          render_repository.with(type_repository.by_slug('topics')).update(topic)

          expect(late_specimens).to eq []
        end

        it 'stops answering with a deleted slug' do
          topic = create_in('topics', name: 'Topic late', slug: 'topic-late')
          create_in('specimens', name: 'Late', score: 1, topic_ids: [topic._id],
                                 category_id: option_id(:category, 'alpha'),
                                 slug: 'late-specimen')

          expect(late_specimens).to eq %w(late-specimen)

          written.delete(['topics', topic])
          render_repository.with(type_repository.by_slug('topics')).delete(topic)

          expect(late_specimens).to eq []
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

        it 'finds them through a hash naming a symbol id' do
          expect(slugs(maker: { _id: makers.by_slug('maker-one')._id.to_s.to_sym }))
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

      describe 'querying through the persisted name' do

        it 'reads the id the store issued' do
          expect(slugs(maker_id: makers.by_slug('maker-one')._id))
            .to match_array %w(arrays scalars)
        end

        it 'reads a stringified id' do
          expect(slugs(maker_id: makers.by_slug('maker-one')._id.to_s))
            .to match_array %w(arrays scalars)
        end

        it 'reads a symbol as the text form of an id' do
          expect(slugs(maker_id: makers.by_slug('maker-one')._id.to_s.to_sym))
            .to match_array %w(arrays scalars)
        end

        it 'reads a select option id' do
          reference = slugs(category: 'alpha')

          expect(reference).not_to be_empty
          expect(slugs(category_id: option_id(:category, 'alpha'))).to eq reference
        end

        def topic_id(slug)
          Locomotive::Steam::ContentEntryRepository.new(
            adapter, site, AdapterParityFixture::LOCALE, type_repository)
            .with(type_repository.by_slug('topics')).by_slug(slug)._id
        end

        it 'reads a lone id on a list name as membership' do
          expect(slugs(topic_ids: topic_id('topic-b'))).to match_array %w(arrays scalars)
        end

        it 'refuses an Array with equality' do
          expect { slugs(topic_ids: [topic_id('topic-a')]) }
            .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
        end

        it 'reads a flat all list element-wise' do
          expect(slugs('topic_ids.all' => [topic_id('topic-a'), topic_id('topic-b')]))
            .to eq %w(scalars)
        end

        it 'refuses a nested list element' do
          [{ 'topic_ids.in' => [[topic_id('topic-a')]] },
           { 'topic_ids.all' => [[topic_id('topic-a')]] }].each do |conditions|
            expect { slugs(conditions) }
              .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
          end
        end

        it 'keeps nil semantics equal to the declared name' do
          expect(slugs(maker_id: nil)).to eq slugs(maker: nil)
        end

        it 'matches nothing through text no store reads as an id' do
          expect(slugs(maker_id: 'zzz')).to eq []
        end

        it 'reads list elements as ids, a null element included' do
          expect(slugs('topic_ids.in' => [nil]))
            .to match_array %w(all-missing arrays embedded explicit-nils)
        end

        it 'refuses an ordering comparison, a Range and a Regexp' do
          [{ 'maker_id.gt' => '' }, { maker_id: 1..10 }, { maker_id: /abc/ }].each do |conditions|
            expect { slugs(conditions) }
              .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
          end
        end

      end

      describe 'querying a many_to_many by equality' do

        def playlist_slugs(conditions)
          repository = Locomotive::Steam::ContentEntryRepository.new(
            adapter, site, AdapterParityFixture::LOCALE, type_repository)

          repository.with(type_repository.by_slug('playlists')).all(conditions).map do |entry|
            entry._slug[AdapterParityFixture::LOCALE]
          end
        end

        def topic(slug)
          repository = Locomotive::Steam::ContentEntryRepository.new(
            adapter, site, AdapterParityFixture::LOCALE, type_repository)

          repository.with(type_repository.by_slug('topics')).by_slug(slug)
        end

        it 'reads a lone operand as the element the list must hold' do
          expect(playlist_slugs(topics: 'topic-a')).to match_array %w(alpha reversed zapped)
        end

        it 'reads ne as the element the list must lack' do
          expect(playlist_slugs('topics.ne' => 'topic-a')).to eq %w(beta)
        end

        it 'reads an entry operand as the same membership element' do
          expect(playlist_slugs(topics: topic('topic-a')))
            .to match_array %w(alpha reversed zapped)
        end

        it 'reads an id document operand as the same membership element' do
          expect(playlist_slugs(topics: { _id: topic('topic-a')._id }))
            .to match_array %w(alpha reversed zapped)
        end

        it 'reads an id document inside in as one element' do
          expect(playlist_slugs('topics.in' => { _id: topic('topic-a')._id }))
            .to match_array %w(alpha reversed zapped)
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
