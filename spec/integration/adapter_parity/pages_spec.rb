require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'
require_relative '../../support/adapter_parity_fixture'
require_relative '../../support/adapter_parity_context'

describe 'Adapter parity' do

  shared_examples_for 'the adapter parity dataset' do

    include_context 'adapter parity dataset access'

    describe 'the page tree' do

      let(:pages) { Locomotive::Steam::PageRepository.new(adapter, site, AdapterParityFixture::LOCALE) }

      it 'exposes the same root' do
        expect(pages.root.fullpath[AdapterParityFixture::LOCALE]).to eq 'index'
      end

      def fullpaths(list)
        list.map { |page| page.fullpath[AdapterParityFixture::LOCALE] }
      end

      # contact sorts before about on position alone, so depth cannot be the
      # only key doing the work.
      it 'orders the whole tree by depth and then position' do
        expect(fullpaths(pages.all)).to eq %w(index contact about content_type_template about/team)
      end

      it 'narrows the tree by the conditions it is given' do
        expect(fullpaths(pages.all('slug.ne' => 'about'))).to eq %w(index contact content_type_template about/team)
        expect(fullpaths(pages.matching_fullpath(%w(about about/team nowhere)))).to match_array %w(about about/team)
      end

      it 'walks the same parent-child hierarchy' do
        team = pages.by_fullpath('about/team')

        expect(team.title[AdapterParityFixture::LOCALE]).to eq 'Team'
        expect(team.depth).to eq 2
        expect(pages.parent_of(team).fullpath[AdapterParityFixture::LOCALE]).to eq 'about'
        expect(fullpaths(pages.ancestors_of(team))).to eq %w(index about about/team)
        expect(fullpaths(pages.children_of(pages.root))).to eq %w(contact about content_type_template)
      end

      it 'finds a page by the handle it declares' do
        expect(pages.by_handle('the-team').fullpath[AdapterParityFixture::LOCALE]).to eq 'about/team'
        expect(fullpaths(pages.only_handle_and_fullpath)).to match_array %w(contact about/team content_type_template)
      end

      # Each store names the target type by its own content type id, so the
      # entry has to reach its template through either spelling.
      it 'finds the template a content entry renders through' do
        entries  = Locomotive::Steam::ContentEntryRepository.new(
          adapter, site, AdapterParityFixture::LOCALE, type_repository)
        entry    = entries.with(type_repository.by_slug('specimens')).by_slug('scalars')
        template = pages.template_for(entry)

        expect(template.fullpath[AdapterParityFixture::LOCALE]).to eq 'content_type_template'
        expect(template.content_entry._slug[AdapterParityFixture::LOCALE]).to eq 'scalars'
        expect(template).not_to be_listed
      end

      it 'reads an editable element by its block and slug' do
        element = pages.editable_element_for(pages.by_fullpath('about'), 'content/banner', 'pitch')

        expect(element.content[AdapterParityFixture::LOCALE]).to eq '<h2>About</h2>'
      end

      # Engine defaults published to false and the Steam entity to true, so a
      # dropped field reads back fine yet disappears from #published.
      it 'keeps publication and listing behaviour' do
        expect(fullpaths(pages.published)).to match_array %w(index contact about content_type_template about/team)

        expect(pages.root).not_to be_listed
        expect(pages.by_fullpath('about')).to be_listed
      end

      def page_source(locale, fullpath)
        repository = Locomotive::Steam::PageRepository.new(adapter, site, locale)

        Locomotive::Steam::PageFinderService.new(repository).find(fullpath).liquid_source.strip
      end

      # Filesystem reads the template file, MongoDB a localized raw_template.
      it 'renders the same source from either store' do
        expect(page_source(:en, 'about')).to eq 'About body en'
        expect(page_source(:fr, 'a-propos')).to eq 'About body fr'
      end

      it 'resolves a localized fullpath in its own locale' do
        french = Locomotive::Steam::PageRepository.new(adapter, site, :fr)

        expect(french.by_fullpath('a-propos').title[:fr]).to eq 'A propos'
        expect(french.by_fullpath('a-propos/team').title[:fr]).to eq 'Team'
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
