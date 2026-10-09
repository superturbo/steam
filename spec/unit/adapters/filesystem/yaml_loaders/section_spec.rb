require 'spec_helper'

require_relative '../../../../../lib/locomotive/steam/adapters/filesystem/yaml_loader.rb'
require_relative '../../../../../lib/locomotive/steam/adapters/filesystem/yaml_loaders/section.rb'

describe Locomotive::Steam::Adapters::Filesystem::YAMLLoaders::Section do

  let(:site_path) { default_fixture_site_path }
  let(:loader)    { described_class.new(site_path) }

  describe '#load' do

    let(:scope) { instance_double('Scope', default_locale: :en) }

    subject { loader.load(scope).sort { |a, b| a[:name] <=> b[:name] } }

    it 'tests various stuff' do
      expect(subject.size).to eq 3
      expect(subject.first[:slug]).to eq('carousel')
      expect(subject[1][:name]).to eq('Footer')
      expect(subject[2][:name]).to eq('Header')
      expect(subject[2][:slug]).to eq('header')
    end

  end

  describe '#load_file' do

    subject { loader.send(:load_file, filepath) }

    describe 'error in the json header' do

      let(:filepath) { File.join(default_fixture_site_path, '..', 'errors', 'section_bad_json_header.liquid') }

      it 'should throw an error' do
        expect { subject }.to raise_error(Locomotive::Steam::TemplateError)
      end

    end

    describe 'json content' do

      let(:filepath) { File.join(default_fixture_site_path, '..', 'errors', 'section_bad_json_content.liquid') }

      it 'should throw an error' do
        expect { subject }.to raise_error(Locomotive::Steam::JsonParsingError)
      end
    end

  end

  describe 'a section file' do

    let(:site_path) { Dir.mktmpdir }
    let(:scope)     { instance_double('Scope', default_locale: :en) }
    let(:path)      { File.join(site_path, 'app', 'views', 'sections', 'promo.liquid') }

    before do
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, "---\nname: Akcija\n---\n".b + body.b)
    end

    after { FileUtils.remove_entry(site_path) }

    context 'that is valid UTF-8' do

      let(:body) { '<p>Ąžuolas</p>' }

      it 'loads its definition and template' do
        section = loader.load(scope).first

        expect(section[:definition][:name]).to eq 'Akcija'
        expect(section[:template]).to eq '<p>Ąžuolas</p>'
      end

    end

    context 'that is not valid UTF-8' do

      let(:body) { "<p>Labas \xFF pasauli</p>" }

      it 'is refused with its path, without its content' do
        expect { loader.load(scope) }.to raise_error(Locomotive::Steam::TemplateError) { |error|
          expect(error.message).to eq 'The file is not valid UTF-8'
          expect(error.template_name).to eq path
          expect(error.source).to be_nil
          expect(error.backtrace).not_to be_empty
        }
      end

    end

  end

  describe 'a section file without a header' do

    let(:site_path) { Dir.mktmpdir }
    let(:scope)     { instance_double('Scope', default_locale: :en) }
    let(:path)      { File.join(site_path, 'app', 'views', 'sections', 'promo.liquid') }

    before do
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "<p>Akcija</p>\n")
    end

    after { FileUtils.remove_entry(site_path) }

    it 'is refused with its path and a backtrace' do
      expect { loader.load(scope) }.to raise_error(Locomotive::Steam::TemplateError) { |error|
        expect(error.message).to eq 'Your file requires a valid YAML or JSON header'
        expect(error.template_name).to eq path
        expect(error.backtrace).not_to be_empty
      }
    end

  end

end
