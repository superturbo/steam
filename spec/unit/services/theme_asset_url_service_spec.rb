require 'spec_helper'

describe Locomotive::Steam::ThemeAssetUrlService do

  let(:checksums)  { { 'stylesheets/main.css' => 'abcdef' } }
  let(:repository) { instance_double('ThemeAssetRepository', checksums: checksums) }
  let(:asset_host) { instance_double('AssetHostService') }
  let(:checksum)   { true }
  let(:service)    { described_class.new(repository, asset_host, checksum) }

  before do
    allow(repository).to receive(:url_for) { |path| "/#{path}" }
    allow(asset_host).to receive(:compute) { |url, version| version ? "#{url}?#{version}" : url }
  end

  describe '#build' do

    subject { service.build('stylesheets/main.css'.dup) }

    it { is_expected.to eq '/stylesheets/main.css?abcdef' }

    context 'the store knows no checksum for it' do
      let(:checksums) { {} }
      it { is_expected.to eq '/stylesheets/main.css' }
    end

    context 'versioning is off' do
      let(:checksum) { false }

      it 'asks the store for nothing' do
        expect(repository).not_to receive(:checksums)
        expect(subject).to eq '/stylesheets/main.css'
      end
    end

    context 'the path carries a query string of its own' do
      subject { service.build('stylesheets/main.css?v=2'.dup) }

      it 'leaves it alone without asking the store' do
        expect(repository).not_to receive(:checksums)
        expect(subject).to eq '/stylesheets/main.css?v=2'
      end
    end

  end

end
