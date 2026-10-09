require 'spec_helper'
require 'haml'

describe Locomotive::Steam::Decorators::TemplateDecorator do

  let(:template_path)   { 'template.liquid' }
  let(:page)            { instance_double('Page', localized_attributes: [], template_path: template_path) }
  let(:locale)          { 'fr' }
  let(:default_locale)  { 'en' }
  let(:decorated)       { described_class.new(page, locale, default_locale) }

  describe '#liquid_source' do

    let(:content) { 'Lorem ipsum' }

    before { allow(File).to receive(:read).and_return(content) }

    subject { decorated.liquid_source.strip }

    it { is_expected.to eq 'Lorem ipsum' }

    context 'Raw template' do

      let(:page) { instance_double('Page', localized_attributes: [:source], source: { en: 'Lorem ipsum [EN]', fr: '' }) }

      it { is_expected.to eq 'Lorem ipsum [EN]' }

    end

    context 'HAML file' do

      let(:template_path) { 'template.liquid.haml' }
      let(:content) { '%p Lorem ipsum' }

      it { is_expected.to eq '<p>Lorem ipsum</p>' }

      context 'incorrect HAML syntax' do

        let(:content) { "foo\n  %p TEST" }

        it 'raises an error' do
          expect { subject }.to raise_error Locomotive::Steam::RenderError
        end

      end

    end

  end

  describe '#liquid_source of a template file' do

    let(:directory)     { Dir.mktmpdir }
    let(:template_path) { File.join(directory, 'card.liquid') }
    let(:snippet)       { instance_double('Snippet', localized_attributes: [], template_path: template_path) }
    let(:decorated)     { described_class.new(snippet, locale, default_locale) }

    before { File.binwrite(template_path, content.b) }

    after { FileUtils.remove_entry(directory) }

    context 'that is valid UTF-8' do

      let(:content) { '<p>Ąžuolas</p>' }

      it { expect(decorated.liquid_source).to eq '<p>Ąžuolas</p>' }

    end

    context 'that is not valid UTF-8' do

      let(:content) { "<p>Labas \xFF pasauli</p>" }

      it 'is refused with its path, without its content' do
        expect { decorated.liquid_source }.to raise_error(Locomotive::Steam::TemplateError) { |error|
          expect(error.message).to eq 'The file is not valid UTF-8'
          expect(error.template_name).to eq template_path
          expect(error.source).to be_nil
          expect(error.backtrace).not_to be_empty
        }
      end

    end

  end

end
