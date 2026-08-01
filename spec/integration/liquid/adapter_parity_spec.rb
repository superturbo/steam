require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'
require_relative '../../support/adapter_parity_fixture'

# The same templates through both stores, against a fixed expected output. A
# shared rendering bug would pass if the two were only compared to each other.
describe 'Liquid adapter parity' do

  shared_examples_for 'the adapter parity dataset rendered' do

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

    describe 'scoping' do

      it 'opens one scope per select option, including the option nothing uses' do
        source = '{% for option in contents.specimens.category_options %}' \
                 '[{{ option }}:{% with_scope category: option %}' \
                 '{{ contents.specimens.count }}:' \
                 '{% for entry in contents.specimens %}{{ entry.name }} {% endfor %}' \
                 '{% endwith_scope %}]{% endfor %}'

        expect(render_liquid(source)).to eq '[alpha:1:Scalars ][beta:1:Arrays ][gamma:0:]'
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

      it 'accepts the legacy string spelling of the same condition' do
        source = %({% with_scope labels.all: "$and: ['x', 'y']" %}) +
                 '{% for entry in contents.specimens %}[{{ entry.name }}]{% endfor %}' \
                 '{% endwith_scope %}'

        expect(render_liquid(source)).to eq '[Arrays]'
      end

    end

  end

  context 'MongoDB' do

    before(:all) { AdapterParityFixture.seed_mongodb! }
    after(:all)  { AdapterParityFixture.cleanup! }

    it_should_behave_like 'the adapter parity dataset rendered' do
      let(:adapter) { AdapterParityFixture.mongodb_adapter }
    end

  end

  context 'Filesystem' do

    it_should_behave_like 'the adapter parity dataset rendered' do
      let(:adapter) { AdapterParityFixture.filesystem_adapter }
    end

  end

end
