require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'
require_relative '../../support/adapter_parity_fixture'
require_relative '../../support/adapter_parity_context'

describe 'Adapter parity' do

  shared_examples_for 'the adapter parity dataset' do

    include_context 'adapter parity dataset access'

    describe 'the sections' do

      let(:sections) { Locomotive::Steam::SectionRepository.new(adapter, site, AdapterParityFixture::LOCALE) }

      def section(slug)
        Locomotive::Steam::SectionFinderService.new(sections).find(slug)
      end

      def drop(slug)
        Locomotive::Steam::Liquid::Drops::Section.new(section(slug), nil)
      end

      # Wagon names a section after its file, Engine stores the name.
      it 'reads back the same identity' do
        gallery = section('gallery')

        expect(gallery.slug).to eq 'gallery'
        expect(gallery.type).to eq 'gallery'
        expect(gallery.name).to eq 'Gallery'
        expect(gallery.definition['settings'].map { |setting| setting['id'] }).to eq %w(columns rows framed)
      end

      # Filesystem reads the template file, MongoDB the stored template.
      it 'renders the same source from either store' do
        expect(section('gallery').liquid_source.strip).to eq '<ul class="gallery"></ul>'
      end

      it 'exposes the same CSS class' do
        expect(drop('gallery').css_class).to eq 'section-gallery'
      end

      it 'reads the content a section states for itself' do
        expect(drop('gallery').settings['columns']).to eq 4
      end

      it 'reads a setting the section turned off as off' do
        expect(drop('gallery').settings['framed']).to eq false
      end

      it 'reads an omitted setting from its declared default' do
        expect(drop('gallery').settings['rows']).to eq 2
      end

      it 'gives a section without stated content nothing to read' do
        expect(drop('footer').settings['columns']).to be_nil
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
