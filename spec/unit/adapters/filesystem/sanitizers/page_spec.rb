require 'spec_helper'

require_relative '../../../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../../../../lib/locomotive/steam/errors.rb'

describe Locomotive::Steam::Adapters::Filesystem::Sanitizers::Page do

  let(:sanitizer) { described_class.new }

  describe '#set_parent_id' do

    let(:page) do
      Locomotive::Steam::Page.new(title: { en: 'Not found' }).tap { |p| p._fullpath = '404' }
    end

    it 'initializes empty ancestry for the 404 page' do
      sanitizer.set_parent_id(page)
      expect(page.parent_ids).to eq []
    end

  end

  describe '#transform_sections_content' do

    # transform_sections_content only relies on its `page`/`locale` arguments,
    # so it can be exercised on a lightweight page stub without the full dataset.
    let(:page) do
      OpenStruct.new(
        sections_dropzone_content: {},
        sections_content:          { en: content },
        template_path:             { en: 'index' }
      )
    end

    subject { sanitizer.transform_sections_content(page, :en) }

    context 'with a valid JSON string' do
      let(:content) { '{"a":1}' }

      it 'parses the string into a Ruby object in place' do
        subject
        expect(page.sections_content[:en]).to eq('a' => 1)
      end
    end

    context 'when the value is already a Hash (not a String)' do
      let(:content) { { 'a' => 1 } }

      it 'leaves it untouched' do
        subject
        expect(page.sections_content[:en]).to eq('a' => 1)
      end
    end

    context 'when an earlier field is already parsed but a later one is still a JSON string' do
      # sections_dropzone_content is a Hash (already parsed), sections_content is
      # still a raw JSON string: the already-parsed field must not stop the loop
      # before the string field gets parsed.
      let(:page) do
        OpenStruct.new(
          sections_dropzone_content: { en: { 'already' => 'parsed' } },
          sections_content:          { en: '{"a":1}' },
          template_path:             { en: 'index' }
        )
      end

      it 'still parses the later string field' do
        subject
        expect(page.sections_content[:en]).to eq('a' => 1)
      end
    end

    context 'with a malformed JSON string' do
      let(:content) { '{ not valid json }' }

      it 'raises a JsonParsingError' do
        expect { subject }.to raise_error(Locomotive::Steam::JsonParsingError)
      end
    end

    context 'with notes between the values' do
      let(:content) { '{"a":1 /* one */}' }

      it { expect { subject }.to raise_error(Locomotive::Steam::JsonParsingError) }
    end

    context 'with text no encoding can read' do
      let(:content) { %({"a":"\xFF"}) }

      it { expect { subject }.to raise_error(Locomotive::Steam::JsonParsingError) }
    end

  end

  describe 'materializing the localized fields' do

    let(:pages)      { [{ _fullpath: 'index' }] }
    let(:site)       { instance_double('Site', _id: 1, default_locale: :en, locales: %i(en fr)) }
    let(:adapter)    { Locomotive::Steam::FilesystemAdapter.new(nil) }
    let(:repository) { Locomotive::Steam::PageRepository.new(adapter, site, :en) }

    before do
      allow(adapter).to receive(:collection).and_return(pages)
      adapter.cache = NoCacheStore.new
    end

    # Page normalization requires these fields even when the source omits them.
    %i(title slug fullpath template_path redirect_url
       sections_content sections_dropzone_content
       seo_title meta_description meta_keywords).each do |name|

      it "materializes #{name} as a localized field" do
        expect(repository.all.first[name]).to respond_to(:translations)
      end

    end

  end

end
