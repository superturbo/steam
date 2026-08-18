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
      ::Liquid::Context.new(assigns, {}, { services: services,
                                           locale:   AdapterParityFixture::LOCALE,
                                           site:     site })
    end

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

      it 'cannot widen the content type scope' do
        source = "{% with_scope content_type_id: 'somewhere-else' %}" \
                 '{% for entry in contents.specimens %}[{{ entry._slug }}]{% endfor %}' \
                 '{% endwith_scope %}'

        expect(render_liquid(source)).to eq ''
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
