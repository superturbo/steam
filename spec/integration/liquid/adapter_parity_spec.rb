require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'
require_relative '../../support/adapter_parity_fixture'

# The same templates through both stores, against a fixed expected output. A
# shared rendering bug would pass if the two were only compared to each other.
describe 'Liquid adapter parity' do

  shared_examples_for 'a store that narrows a window' do

    it 'builds only the rows the window selects' do
      expect(entries_built { names('limit: 2') }).to eq 2
    end

    it 'builds only the rows an offset leaves' do
      expect(entries_built { names('offset: 4') }).to eq 2
    end

    it 'builds only the visible rows when the loop is unlimited' do
      expect(entries_built { names('') }).to eq 6
    end

  end

  # Filesystem materializes its full dataset before filtering or slicing.
  shared_examples_for 'a store that builds every entry when it loads' do

    it 'builds every row for a window' do
      expect(entries_built { names('limit: 2') }).to eq 7
    end

    it 'builds every row for an offset' do
      expect(entries_built { names('offset: 4') }).to eq 7
    end

    it 'builds every row when the loop is unlimited' do
      expect(entries_built { names('') }).to eq 7
    end

  end

  shared_examples_for 'the adapter parity dataset rendered' do |store_behaviour|

    let(:site)     { Locomotive::Steam::SiteRepository.new(adapter).by_handle_or_domain('adapter-parity', nil) }
    let(:services) { Locomotive::Steam::Services.build_instance }
    let(:current_page) { nil }

    let(:assigns) do
      { 'contents'     => Locomotive::Steam::Liquid::Drops::ContentTypes.new,
        'fullpath'     => '/',
        'current_page' => current_page }
    end

    let(:context) do
      ::Liquid::Context.new(assigns, {}, { services:    services,
                                           locale:      AdapterParityFixture::LOCALE,
                                           site:        site,
                                           file_system: file_system })
    end

    let(:file_system) { Locomotive::Steam::Liquid::FileSystem.new(snippet_finder: services.snippet_finder) }

    before do
      services.locale                    = AdapterParityFixture::LOCALE
      services.repositories.adapter      = adapter
      services.repositories.current_site = site
    end

    def render_liquid(source)
      render_template(source, context)
    end

    it 'reaches a content type named by a variable' do
      source = "{% assign type = 'specimens' %}" \
               '{% for entry in contents[type] %}[{{ entry.name }}]{% endfor %}'

      expect(render_liquid(source)).to eq '[All missing][Arrays][Embedded][Explicit nils][Scalars][Zero]'
    end

    it 'renders the label of the option an entry holds' do
      source = '{% for entry in contents.specimens %}[{{ entry.category }}|{{ entry.tier }}]{% endfor %}'

      expect(render_liquid(source)).to eq '[|][beta|Silver][|Gold][|][alpha|Gold][|]'
    end

    describe 'a window of many_to_many owners' do

      it 'renders every list in its owner sequence' do
        source = '{% for playlist in contents.playlists limit: 3 %}' \
                 '[{{ playlist._slug }}:' \
                 '{% for topic in playlist.topics %}{{ topic._slug }},{% endfor %}]' \
                 '{% endfor %}'

        expect(render_liquid(source))
          .to eq '[alpha:topic-a,][beta:topic-b,][reversed:topic-b,topic-a,]'
      end

      it 'renders an inner window from the head of each sequence' do
        source = '{% for playlist in contents.playlists limit: 3 %}' \
                 '[{{ playlist._slug }}:' \
                 '{% for topic in playlist.topics limit: 1 %}{{ topic._slug }}{% endfor %}]' \
                 '{% endfor %}'

        expect(render_liquid(source))
          .to eq '[alpha:topic-a][beta:topic-b][reversed:topic-b]'
      end

      it 'lets a hidden head yield inside the window' do
        source = '{% for playlist in contents.playlists limit: 4 %}' \
                 '[{{ playlist._slug }}:' \
                 '{% for topic in playlist.topics limit: 1 %}{{ topic._slug }}{% endfor %}]' \
                 '{% endfor %}'

        expect(render_liquid(source))
          .to eq '[alpha:topic-a][beta:topic-b][reversed:topic-b][zapped:topic-a]'
      end

      it 'answers first with the head of each sequence' do
        source = '{% for playlist in contents.playlists limit: 4 %}' \
                 '[{{ playlist._slug }}:{{ playlist.topics.first._slug }}]' \
                 '{% endfor %}'

        expect(render_liquid(source))
          .to eq '[alpha:topic-a][beta:topic-b][reversed:topic-b][zapped:topic-a]'
      end

      it 'answers emptiness behind a hidden head' do
        source = '{% for playlist in contents.playlists limit: 4 %}' \
                 '[{{ playlist._slug }}:' \
                 '{% if playlist.topics == empty %}-{% else %}+{% endif %}]' \
                 '{% endfor %}'

        expect(render_liquid(source))
          .to eq '[alpha:+][beta:+][reversed:+][zapped:+]'
      end

    end

    describe 'a window of has_many owners' do

      it 'renders every group in its own order' do
        source = '{% for maker in contents.makers limit: 4 %}' \
                 '[{{ maker._slug }}:' \
                 '{% for specimen in maker.specimens %}{{ specimen._slug }},{% endfor %}]' \
                 '{% endfor %}'

        expect(render_liquid(source)).to eq(
          '[0123456789abcdef01234567:][maker-one:scalars,arrays,]' \
          '[maker-three:][maker-two:embedded,]')
      end

    end

    describe 'paginating' do

      let(:source) do
        '{% paginate contents.specimens by 5 %}' \
        '{% for entry in paginate.collection %}[{{ entry.name }}]{% endfor %}' \
        '{% endpaginate %}'
      end

      it 'renders the first page' do
        expect(render_liquid(source)).to eq '[All missing][Arrays][Embedded][Explicit nils][Scalars]'
      end

      context 'on the second page' do

        let(:current_page) { 2 }

        it 'renders what the first page left' do
          expect(render_liquid(source)).to eq '[Zero]'
        end

      end

      it 'paginates a has_many association' do
        source = "{% with_scope _slug: 'maker-one' %}" \
                 '{% assign maker = contents.makers.first %}' \
                 '{% endwith_scope %}' \
                 '{% paginate maker.specimens by 1 %}' \
                 '{% for entry in paginate.collection %}[{{ entry.name }}]{% endfor %}' \
                 '{% endpaginate %}'

        expect(render_liquid(source)).to eq '[Scalars]'
      end

    end

    # The six specimens order as: All missing, Arrays, Embedded, Explicit nils,
    # Scalars, Zero.
    describe 'slicing a loop' do

      def names(markup, before = '')
        render_liquid("#{before}{% for entry in contents.specimens #{markup} %}" \
                      '[{{ entry.name }}]{% endfor %}')
      end

      it 'takes the first rows' do
        expect(names('limit: 2')).to eq '[All missing][Arrays]'
      end

      it 'skips rows' do
        expect(names('offset: 4')).to eq '[Scalars][Zero]'
      end

      it 'skips and then takes' do
        expect(names('offset: 1 limit: 2')).to eq '[Arrays][Embedded]'
      end

      it 'stops at the end when asked for more than there is' do
        expect(names('limit: 100')).to eq '[All missing][Arrays][Embedded][Explicit nils][Scalars][Zero]'
      end

      it 'renders nothing when the scope matches nothing' do
        source = "{% with_scope name: 'nobody' %}" \
                 '{% for entry in contents.specimens limit: 2 %}[{{ entry.name }}]{% endfor %}' \
                 '{% endwith_scope %}'

        expect(render_liquid(source)).to eq ''
      end

      it 'rejects the internal content type field' do
        source = "{% with_scope content_type_id: 'somewhere-else' %}" \
                 '{% for entry in contents.specimens %}[{{ entry._slug }}]{% endfor %}' \
                 '{% endwith_scope %}'

        expect { render_liquid(source) }.to raise_error(::Liquid::Error)
      end

      it 'reverses the rows it took, not the ones it skipped' do
        expect(names('reversed limit: 2')).to eq '[Arrays][All missing]'
      end

      it 'resumes where the previous loop over the same collection stopped' do
        first = '{% for entry in contents.specimens limit: 2 %}{% endfor %}'

        expect(names('offset: continue limit: 2', first)).to eq '[Embedded][Explicit nils]'
      end

      it 'slices a table row loop the same way' do
        source = '{% tablerow entry in contents.specimens limit: 2 %}' \
                 '[{{ entry.name }}]{% endtablerow %}'

        expect(render_liquid(source).scan(/\[[^\]]+\]/).join).to eq '[All missing][Arrays]'
      end

      it 'starts at the beginning when asked to start before it' do
        expect(names('offset: -1')).to eq '[All missing][Arrays][Embedded][Explicit nils][Scalars][Zero]'
      end

      it 'renders nothing for an empty window' do
        expect(names('limit: 0')).to eq ''
      end

      it 'falls to the else branch when the window selects no rows' do
        source = '{% for entry in contents.specimens limit: 0 %}[{{ entry.name }}]' \
                 '{% else %}none{% endfor %}'

        expect(render_liquid(source)).to eq 'none'
      end

      describe 'the rows it builds' do

        def entries_built
          built = 0

          allow_any_instance_of(Locomotive::Steam::Models::Mapper)
            .to receive(:to_entity).and_wrap_original do |original, *args|
              original.call(*args).tap do |entity|
                built += 1 if entity.is_a?(Locomotive::Steam::ContentEntry)
              end
            end

          yield

          built
        end

        it_behaves_like store_behaviour

      end

    end

    describe 'scoping' do

      it 'opens one scope per select option, including the option nothing uses' do
        source = '{% for option in contents.specimens.category_options %}' \
                 '[{{ option }}:{% with_scope category: option %}' \
                 '{{ contents.specimens.count }}:' \
                 '{% for entry in contents.specimens %}{{ entry.name }} {% endfor %}' \
                 '{% endwith_scope %}]{% endfor %}'

        expect(render_liquid(source)).to eq '[alpha:1:Scalars ][beta:1:Arrays ][gamma:0:]'
      end

      it 'renders a field the store never held as empty text' do
        source = '{% for entry in contents.specimens %}[{{ entry.title }}]{% endfor %}'

        expect(render_liquid(source))
          .to eq '[][Arrays en][Embedded en][][Scalars en][]'
      end

      it 'renders a timestamp the store never held as empty text' do
        source = "{% assign entry = contents.specimens.first %}[{{ entry.created_at }}]"

        expect(render_liquid(source)).to eq '[]'
      end

      it 'reaches hidden entries when the template asks for them' do
        source = '{% with_scope _visible: false %}' \
                 '{% for entry in contents.specimens %}[{{ entry.name }}]{% endfor %}' \
                 '{% endwith_scope %}'

        expect(render_liquid(source)).to eq '[Hidden]'
      end

      describe 'a nil literal' do

        def names(scope)
          render_liquid("{% with_scope #{scope} %}" \
                        '{% for entry in contents.specimens %}[{{ entry.name }}]{% endfor %}' \
                        '{% endwith_scope %}')
        end

        it 'includes hidden entries when nil disables the visibility filter' do
          expect(names('_visible: nil'))
            .to eq '[All missing][Arrays][Embedded][Explicit nils][Hidden][Scalars][Zero]'
        end

        it 'matches a missing, null, or null-holding association' do
          expect(names('topics: nil'))
            .to eq '[All missing][Arrays][Embedded][Explicit nils]'
        end

        it 'keeps nil as a list operand' do
          expect(names("labels.in: [nil, 'y']"))
            .to eq '[All missing][Arrays][Explicit nils][Scalars][Zero]'
        end

        it 'uses the default order when order_by is nil' do
          expect(names('order_by: nil')).to eq '[All missing][Arrays][Embedded][Explicit nils][Scalars][Zero]'
        end

      end

      it 'finds an entry by a value shaped like a criterion key' do
        source = %q({% with_scope name: 'a.in: b' %}) +
                 '{% for entry in contents.quoted %}[{{ entry.name }}]{% endfor %}' \
                 '{% endwith_scope %}'

        expect(render_liquid(source)).to eq '[a.in: b]'
      end

      # all requires every operand; stored order and extra values do not matter.
      it 'narrows an array field to the rows holding every listed value' do
        names = ->(scope) do
          render_liquid("{% with_scope #{scope} %}" \
                        '{% for entry in contents.specimens %}[{{ entry.name }}]{% endfor %}' \
                        '{% endwith_scope %}')
        end

        expect(names.call("labels.all: ['x', 'y']")).to eq '[Arrays]'
        expect(names.call("labels: 'x'")).to eq '[Arrays][Embedded]'
      end

    end

    describe 'the content type a with_scope block serves' do

      let(:specimen_loop)   { '{% for entry in contents.specimens %}(s:{{ entry.name }}){% endfor %}' }
      let(:topic_loop)      { '{% for entry in contents.topics %}(t:{{ entry.name }}){% endfor %}' }
      let(:maker_specimens) { '{% for entry in maker.specimens %}[{{ entry.name }}]{% endfor %}' }

      def pick(variable, type, slug)
        "{% with_scope _slug: '#{slug}' %}{% assign #{variable} = contents.#{type}.first %}{% endwith_scope %}"
      end

      def scoped(block, criteria, before: '')
        render_liquid("#{before}{% with_scope #{criteria} %}#{block}{% endwith_scope %}")
      end

      describe 'the first query that uses the criteria' do

        it 'claims them for a contents collection it enumerates' do
          expect(scoped(specimen_loop + topic_loop, "name: 'Scalars'"))
            .to eq '(s:Scalars)(t:Topic a)(t:Topic b)'
        end

        it 'claims them for a collection it counts' do
          expect(scoped("{{ contents.specimens.size }}#{topic_loop}", "name: 'Scalars'"))
            .to eq '1(t:Topic a)(t:Topic b)'
        end

        it 'claims them for a collection it takes the first entry of' do
          expect(scoped("{{ contents.specimens.first.name }}#{topic_loop}", "name: 'Scalars'"))
            .to eq 'Scalars(t:Topic a)(t:Topic b)'
        end

        it 'claims them for the target type of a has_many' do
          expect(scoped(maker_specimens + specimen_loop + topic_loop, "name: 'Scalars'",
                        before: pick('maker', 'makers', 'maker-one')))
            .to eq '[Scalars](s:Scalars)(t:Topic a)(t:Topic b)'
        end

        it 'claims them for the target type of a many_to_many' do
          block = '{% for entry in playlist.topics %}[{{ entry.name }}]{% endfor %}' \
                  "#{topic_loop}{{ contents.specimens.size }}"

          expect(scoped(block, "name: 'Topic a'", before: pick('playlist', 'playlists', 'reversed')))
            .to eq '[Topic a](t:Topic a)6'
        end

        it 'validates a name only in the collection that receives the criteria' do
          expect(scoped(specimen_loop + topic_loop, "maker: 'maker-one'"))
            .to eq '(s:Arrays)(s:Scalars)(t:Topic a)(t:Topic b)'
        end

      end

      it 'claims nothing by reading a collection it does not query' do
        expect(scoped("{% assign listed = maker.specimens %}#{topic_loop}", "name: 'Topic a'",
                      before: pick('maker', 'makers', 'maker-one')))
          .to eq '(t:Topic a)'
      end

      describe 'an association after the claim' do

        it 'receives the criteria when its target type is the claimed type' do
          expect(scoped(specimen_loop + maker_specimens, "name: 'Scalars'",
                        before: pick('maker', 'makers', 'maker-one')))
            .to eq '(s:Scalars)[Scalars]'
        end

        it 'receives them when its field name is the claimed slug' do
          block = '{% for entry in contents.chapters %}(c:{{ entry.name }}){% endfor %}' \
                  '{% for entry in playlist.chapters %}[{{ entry.name }}]{% endfor %}'

          expect(scoped(block, "name: 'Topic a'", before: pick('playlist', 'playlists', 'alpha')))
            .to eq '[Topic a]'
        end

        it 'receives none otherwise' do
          block = '{% for maker in contents.makers %}' \
                  '{% for entry in maker.specimens %}[{{ entry.name }}]{% endfor %}{% endfor %}'

          expect(scoped(block, "name: 'Maker one'")).to eq '[Scalars][Arrays]'
        end

      end

      it 'never passes the criteria to a belongs_to' do
        expect(scoped('{{ badge.maker.name }}', "name: 'Nobody'", before: pick('badge', 'badges', 'gold')))
          .to eq 'Maker one'
      end

      describe 'the Liquid scope that holds the claim' do

        let(:criteria) { "name.in: ['Scalars', 'Topic a']" }

        it 'keeps the claim of a for collection in a later nested scope' do
          expect(scoped("#{specimen_loop}{% for i in (1..1) %}#{topic_loop}{% endfor %}", criteria))
            .to eq '(s:Scalars)(t:Topic a)(t:Topic b)'
        end

        it 'keeps the claim of a tablerow collection for the rest of the block' do
          tablerow = '{% tablerow entry in contents.specimens %}(s:{{ entry.name }}){% endtablerow %}'

          expect(scoped(tablerow + topic_loop, criteria).scan(/\([st]:[^)]*\)/))
            .to eq ['(s:Scalars)', '(t:Topic a)', '(t:Topic b)']
        end

        it 'forgets a first query made inside a loop body' do
          expect(scoped("{% for i in (1..1) %}#{specimen_loop}{% endfor %}#{topic_loop}", criteria))
            .to eq '(s:Scalars)(t:Topic a)'
        end

        it 'forgets a first query made inside an include' do
          expect(scoped("{% include 'specimen_names' %}#{topic_loop}", criteria))
            .to eq '(s:Scalars)(t:Topic a)'
        end

      end

    end

  end

  context 'MongoDB' do

    before(:all) { AdapterParityFixture.seed_mongodb! }
    after(:all)  { AdapterParityFixture.cleanup! }

    it_should_behave_like 'the adapter parity dataset rendered',
                          'a store that narrows a window' do
      let(:adapter) { AdapterParityFixture.mongodb_adapter }
    end

  end

  context 'Filesystem' do

    it_should_behave_like 'the adapter parity dataset rendered',
                          'a store that builds every entry when it loads' do
      let(:adapter) { AdapterParityFixture.filesystem_adapter }
    end

  end

end
