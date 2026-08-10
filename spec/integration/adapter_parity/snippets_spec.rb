require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'
require_relative '../../support/adapter_parity_fixture'
require_relative '../../support/adapter_parity_context'

describe 'Adapter parity' do

  shared_examples_for 'the adapter parity dataset' do

    include_context 'adapter parity dataset access'

    describe 'the snippets' do

      def snippets(locale)
        Locomotive::Steam::SnippetRepository.new(adapter, site, locale)
      end

      def snippet(slug, locale)
        Locomotive::Steam::SnippetFinderService.new(snippets(locale)).find(slug)
      end

      # A file may be named more loosely than the slug it is served under, so
      # both stores have to slugify it the same way.
      it 'holds the same snippets under the same slugs' do
        expect(snippets(:en).all.map(&:slug)).to match_array %w(a_complicated-one banner greeting)
        expect(snippet('a_complicated-one', :en).liquid_source.strip).to eq 'Complicated en'
      end

      it 'reads back the same identity' do
        expect(snippet('greeting', :en).slug).to eq 'greeting'
        expect(snippet('greeting', :en).name).to eq 'Greeting'
      end

      # Filesystem keeps a template path per locale, MongoDB a template.
      it 'renders each locale from its own source' do
        expect(snippet('greeting', :en).liquid_source.strip).to eq 'Greeting en'
        expect(snippet('greeting', :fr).liquid_source.strip).to eq 'Greeting fr'
      end

      # One store is missing a file where the other is missing a key, so each
      # reaches the default locale by its own route.
      it 'falls back to the default locale where a locale is absent' do
        expect(snippet('banner', :fr).liquid_source.strip).to eq 'Banner en'
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
