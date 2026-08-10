require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'
require_relative '../../support/adapter_parity_fixture'
require_relative '../../support/adapter_parity_context'

describe 'Adapter parity' do

  shared_examples_for 'the adapter parity dataset' do

    include_context 'adapter parity dataset access'

    describe 'the theme assets' do

      let(:assets) { Locomotive::Steam::ThemeAssetRepository.new(adapter, site, AdapterParityFixture::LOCALE) }
      let(:path)   { 'stylesheets/parity.css' }
      let(:served) { filesystem? ? "/#{path}" : "/sites/#{site._id}/theme/#{path}" }

      # Filesystem knows an asset by the file it read, MongoDB by its local path.
      def asset_identity(asset)
        [File.basename(asset[:local_path] || asset[:source]), asset.folder]
      end

      it 'holds only the files a store serves' do
        expect(assets.all.map { |asset| asset_identity(asset) }).to eq [['parity.css', 'stylesheets']]
      end

      # The fixture site sets no fallback asset version, isolating the checksum.
      def theme_asset_url(checksum)
        host = Locomotive::Steam::AssetHostService.new(nil, site, nil)

        Locomotive::Steam::ThemeAssetUrlService.new(assets, host, checksum).build(path.dup)
      end

      it 'builds the URL its own store serves from' do
        expect(theme_asset_url(false)).to eq served
      end

      # Wagon computes local checksums when pushing; Filesystem does not store them.
      it 'versions the URL by what its store knows of the file' do
        expected = filesystem? ? served : "#{served}?#{Digest::MD5.hexdigest("body { color: #333; }\n")}"

        expect(theme_asset_url(true)).to eq expected
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
