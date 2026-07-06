require 'spec_helper'

require_relative '../../../../../lib/locomotive/steam/adapters/filesystem/sanitizer.rb'
require_relative '../../../../../lib/locomotive/steam/adapters/filesystem/sanitizers/page.rb'
require_relative '../../../../../lib/locomotive/steam/errors.rb'

describe Locomotive::Steam::Adapters::Filesystem::Sanitizers::Page do

  let(:sanitizer) { described_class.new }

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

  end

end
