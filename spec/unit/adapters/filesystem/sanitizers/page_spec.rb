require 'spec_helper'

require_relative '../../../../../lib/locomotive/steam/adapters/filesystem/sanitizer.rb'
require_relative '../../../../../lib/locomotive/steam/adapters/filesystem/sanitizers/page.rb'
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

end
