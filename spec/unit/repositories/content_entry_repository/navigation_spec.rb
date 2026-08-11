require 'spec_helper'

require_relative '../../../support/content_entry_repository_context'

describe Locomotive::Steam::ContentEntryRepository do

  include_context 'content entry repository'

  describe '#next and #previous' do

    it 'have nothing to look for without an entry' do
      expect(repository.next(nil)).to be_nil
      expect(repository.previous(nil)).to be_nil
    end

    describe 'over a type ordered by the slug itself' do

      let(:type) do
        build_content_type('Articles', order_by: { _slug: 'asc' }, label_field_name: :title,
                           fields: _fields, fields_with_default: [],
                           fields_by_name: { title: instance_double('Field', name: :title, type: :string) })
      end

      let(:entries) do
        [{ content_type_id: 1, _position: 0, _label: 'Alpha' },
         { content_type_id: 1, _position: 1, _label: 'Bravo' }]
      end

      before { repository.with(type) }

      it 'queries once because a slug identifies one entry' do
        alpha = repository.by_slug('alpha')
        allow(repository).to receive(:first).and_call_original

        expect(repository.next(alpha)._slug[:en]).to eq 'bravo'
        expect(repository).to have_received(:first).once
      end

    end

    describe 'over the order a manually sorted type has' do

      let(:type) do
        build_content_type('Articles', order_by: { _position: 'asc' }, label_field_name: :title,
                           fields: _fields, fields_with_default: [],
                           fields_by_name: { title: instance_double('Field', name: :title, type: :string) })
      end

      # Slug order would read alpha, mike, zulu.
      let(:entries) do
        [{ content_type_id: 1, _position: 0, _label: 'Zulu' },
         { content_type_id: 1, _position: 1, _label: 'Alpha' },
         { content_type_id: 1, _position: 2, _label: 'Mike' }]
      end

      before { repository.with(type) }

      it 'walks the positions and stops at their ends' do
        expect(repository.next(repository.by_slug('alpha'))._slug[:en]).to eq 'mike'
        expect(repository.previous(repository.by_slug('alpha'))._slug[:en]).to eq 'zulu'
        expect(repository.previous(repository.by_slug('zulu'))).to be_nil
        expect(repository.next(repository.by_slug('mike'))).to be_nil
      end

    end

  end

  describe '#all without a runtime order' do

    let(:type) do
      build_content_type('Chapters', order_by: { part: 'asc' }, label_field_name: :title,
                         fields: _fields, fields_with_default: [],
                         fields_by_name: { part:  instance_double('Field', name: :part,  type: :string),
                                           title: instance_double('Field', name: :title, type: :string) })
    end

    # Input and slug order disagree within part "a"; Alpha sorts last by part.
    let(:entries) do
      [{ content_type_id: 1, _position: 0, _label: 'Alpha', part: 'b' },
       { content_type_id: 1, _position: 1, _label: 'Zulu',  part: 'a' },
       { content_type_id: 1, _position: 2, _label: 'Mike',  part: 'a' }]
    end

    it 'follows the type default and breaks its tie by slug' do
      expect(repository.with(type).all.map { |entry| entry._slug[:en] }).to eq %w(mike zulu alpha)
    end

  end

end
