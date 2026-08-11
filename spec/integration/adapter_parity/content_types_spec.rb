require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'
require_relative '../../support/adapter_parity_fixture'
require_relative '../../support/adapter_parity_context'

describe 'Adapter parity' do

  shared_examples_for 'the adapter parity dataset' do

    include_context 'adapter parity dataset access'

    describe 'the content types' do

      let(:specimens) { type_repository.by_slug('specimens') }

      it 'holds the same types under the same slugs' do
        expect(type_repository.all.map(&:slug))
          .to match_array %w(chapters makers quoted reverse_chapters specimens submissions topics)
      end

      it 'reads what the fixture says about a type and its fields' do
        expect(specimens.description).to eq 'Every field state covered by adapter parity'
        expect(type_repository.fields_for(specimens).by_name('name').hint).to eq 'The name the entry is labelled by'
        expect(type_repository.look_for_unique_fields(specimens).keys).to eq %w(name)
      end

      it 'reads a localized select option in each locale' do
        options = type_repository.select_options(specimens, :tier)

        expect(options.map { |option| option.name.translations })
          .to eq [{ 'en' => 'Gold', 'fr' => 'Or' }, { 'en' => 'Silver', 'fr' => 'Argent' },
                  { 'en' => 'R&D', 'fr' => 'R&D fr' }]
      end

      # A name declared without a locale is stored differently by each side, and
      # still has to answer the same when a locale asks for it.
      it 'reads a select option declared without a locale' do
        expect(type_repository.select_options(specimens, :category).map { |option| option.name[:en] })
          .to eq %w(alpha beta gamma)
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
