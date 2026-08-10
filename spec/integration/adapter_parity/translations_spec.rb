require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'
require_relative '../../support/adapter_parity_fixture'
require_relative '../../support/adapter_parity_context'

describe 'Adapter parity' do

  shared_examples_for 'the adapter parity dataset' do

    include_context 'adapter parity dataset access'

    describe 'the translations' do

      def translations(locale)
        Locomotive::Steam::TranslationRepository.new(adapter, site, locale)
      end

      def translator(locale)
        Locomotive::Steam::TranslatorService.new(translations(locale), locale)
      end

      it 'holds the same keys in both stores' do
        expect(translations(:en).group_by_key.keys)
          .to match_array %w(adapter_parity_english_only hello_name powered_by)
      end

      it 'finds a translation by its key' do
        expect(translations(:en).by_key('powered_by').values)
          .to eq('en' => 'Powered by', 'fr' => 'Propulsé par')
      end

      it 'translates a key in each locale' do
        expect(translator(:en).translate('powered_by')).to eq 'Powered by'
        expect(translator(:fr).translate('powered_by')).to eq 'Propulsé par'
      end

      # The value is Liquid, so both stores have to keep it renderable.
      it 'renders a translation against the given options' do
        expect(translator(:fr).translate('hello_name', 'name' => 'Ada')).to eq 'Bonjour Ada'
      end

      # Unlike a snippet, a translation does not fall back to the default
      # locale; the key itself is the answer. It is namespaced so that no I18n
      # entry another gem registers can stand in for it.
      it 'answers with the key where a locale is absent' do
        expect(translator(:fr).translate('adapter_parity_english_only')).to eq 'adapter_parity_english_only'
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
