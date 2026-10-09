require 'spec_helper'

require_relative '../../../../../lib/locomotive/steam/adapters/filesystem/yaml_loader.rb'
require_relative '../../../../../lib/locomotive/steam/adapters/filesystem/yaml_loaders/site.rb'

describe Locomotive::Steam::Adapters::Filesystem::YAMLLoaders::Site do

  let(:site_path) { default_fixture_site_path }
  let(:loader)    { described_class.new(site_path) }

  describe '#load' do

    subject { loader.load(nil).first }

    it { expect(subject[:name]).to eq 'Sample site' }

    describe '#metafields_schema' do

      subject { loader.load(nil).first[:metafields_schema] }

      it 'loads the full schema' do
        expect(subject.count).to eq 4
      end

    end

    context 'a different environment' do

      let(:loader) { described_class.new(site_path, :production) }

      it 'completes the data with the ones from the production environment' do
        expect(subject[:name]).to eq('My awesome site')
      end

      it 'localizes the sections_content from the production environment' do
        allow(loader).to receive(:_load).with(File.join(site_path, 'config', 'site.yml')).and_return(name: 'Test', locales: ['fr'])
        allow(loader).to receive(:_load).with(File.join(site_path, 'config', 'metafields_schema.yml')).and_return(nil)
        expect(subject[:sections_content]).to eq('fr' => { 'header' => { 'settings' => {
          'title' => 'Hello world' } } })
      end

    end

  end

  describe 'a site file' do

    let(:site_path) { Dir.mktmpdir }
    let(:path)      { File.join(site_path, 'config', 'site.yml') }

    before do
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, "name: ".b + name.b + "\nlocales: [lt]\n".b)
    end

    after { FileUtils.remove_entry(site_path) }

    context 'that is valid UTF-8' do

      let(:name) { 'Ąžuolynas' }

      it { expect(loader.load(nil).first[:name]).to eq 'Ąžuolynas' }

    end

    context 'that is not valid UTF-8' do

      let(:name) { "\xC1\xFEuolynas" }

      it 'is refused with its path, without its content' do
        expect { loader.load(nil) }.to raise_error(Locomotive::Steam::TemplateError) { |error|
          expect(error.message).to eq 'The file is not valid UTF-8'
          expect(error.template_name).to eq path
          expect(error.source).to be_nil
          expect(error.backtrace).not_to be_empty
        }
      end

    end

  end

end
