require 'spec_helper'

require_relative '../../../../../lib/locomotive/steam/adapters/filesystem/yaml_loader.rb'
require_relative '../../../../../lib/locomotive/steam/adapters/filesystem/yaml_loaders/page.rb'

describe Locomotive::Steam::Adapters::Filesystem::YAMLLoaders::Page do

  let(:site_path) { default_fixture_site_path }
  let(:loader)    { described_class.new(site_path) }

  describe '#load' do

    let(:scope) { instance_double('Scope', locale: :fr, default_locale: :en, locales: [:en, :fr]) }

    subject { loader.load(scope).sort { |a, b| a[:_fullpath] <=> b[:_fullpath] } }

    it 'tests various stuff' do
      expect(subject.size).to eq 36
      expect(subject.first[:title]).to eq(en: 'Page not found', fr: 'Page non trouvée')
      expect(subject[23][:is_layout]).to eq true
      expect(subject[23][:listed]).to eq false
      expect(subject[23][:published]).to eq false
      expect(subject[24][:slug]).to eq(en: 'music', fr: 'notre-musique')
      expect(subject[25][:_fullpath]).to eq 'songs'
      expect(subject[25][:template_path]).to eq(en: false)
    end

    context 'a different environment' do

      let(:env)     { :production }
      let(:loader)  { described_class.new(site_path, env) }

      it 'completes the data with the ones from the production environment' do
        expect(subject.size).to eq 37
        expect(subject[21][:title]).to eq(en: 'Home page', fr: "Ma page d'accueil en production")
      end

      describe 'invalid json' do

        let(:env) { :staging }

        it 'raises a parsing exception' do
          expect { subject }.to raise_exception(Locomotive::Steam::JsonParsingError)
        end

      end

    end

    context 'region locales' do

      let(:env)    { :regions }
      let(:loader) { described_class.new(site_path, env) }
      let(:scope)  { instance_double('Scope', locale: :en, default_locale: :en, locales: [:en, :'pl-PL']) }

      it 'loads page data stored under a region-locale folder' do
        index = subject.find { |page| page[:_fullpath] == 'index' }
        expect(index[:title]).to include('pl-PL': 'Strona główna')
      end

    end

    context 'a data file under an unconfigured locale' do

      let(:env)         { :ignored_locale }
      let(:loader)      { described_class.new(site_path, env) }
      let(:scope)       { instance_double('Scope', locale: :en, default_locale: :en, locales: [:en, :fr]) }
      let(:broken_json) { File.join(site_path, 'data', 'ignored_locale', 'pages', 'de', 'broken.json') }

      it 'is skipped without parsing its json' do
        expect(File).to exist(broken_json)
        expect { subject }.not_to raise_error
      end

    end

  end

  describe 'a page file' do

    let(:site_path) { Dir.mktmpdir }
    let(:scope)     { instance_double('Scope', locale: :en, default_locale: :en, locales: [:en]) }
    let(:path)      { File.join(site_path, 'app', 'views', 'pages', 'index.liquid') }
    let(:header)    { "---\ntitle: Pradžia\n---\n" }
    let(:body)      { '<p>Labas</p>' }

    before do
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, header.b + body.b)
    end

    after { FileUtils.remove_entry(site_path) }

    context 'that is valid UTF-8' do

      let(:body) { '<p>Ąžuolas</p>' }

      it 'loads its attributes' do
        expect(loader.load(scope).first[:title]).to eq(en: 'Pradžia')
      end

    end

    { 'no header' => '', 'an empty header' => "---\n---\n" }.each do |description, empty|

      context "with #{description}" do

        let(:header) { empty }

        it 'loads the page with the attributes of its path' do
          expect(loader.load(scope).first[:title]).to eq(en: 'Index')
        end

      end

    end

    { 'a text' => 'Home page', 'a list' => '- Home', 'an explicit null' => '~', 'only a comment' => '# soon' }.each do |description, value|

      context "whose header holds #{description}" do

        let(:header) { "---\n#{value}\n---\n" }

        it 'is refused with its path' do
          expect { loader.load(scope) }.to raise_error(Locomotive::Steam::TemplateError) { |error|
            expect(error.message).to eq 'The header must hold attributes'
            expect(error.template_name).to eq path
            expect(error.backtrace).not_to be_empty
          }
        end

      end

    end

    context 'whose header names an attribute by a number' do

      let(:header) { "---\n1: value\n---\n" }

      it 'is refused with its path' do
        expect { loader.load(scope) }.to raise_error("Malformed YAML in this file #{path}, error: every key must be text")
      end

    end

    context 'whose header cannot be parsed' do

      let(:header) { "---\ntitle: [unclosed\n---\n" }

      it 'is refused with its path and the parser message' do
        expect { loader.load(scope) }.to raise_error(/\AMalformed YAML in this file #{Regexp.escape(path)}, error: .*flow sequence/)
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

end
