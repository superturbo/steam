require 'spec_helper'

require_relative '../../../support/content_entry_repository_context'

describe Locomotive::Steam::ContentEntryRepository do

  include_context 'content entry repository'

  describe '#conditions_without_order_by' do

    let(:conditions) { {} }

    subject { repository.with(type).send(:conditions_without_order_by, conditions) }

    def prepared_for(conditions)
      repository.with(type).send(:conditions_without_order_by, conditions).first
    end

    it { is_expected.to eq([{ '_visible' => true, 'content_type_id' => 1 }, nil]) }

    context 'the _visible condition' do

      it 'keeps an explicit true' do
        expect(prepared_for('_visible' => true)).to include('_visible' => true)
      end

      it 'keeps an explicit false' do
        expect(prepared_for('_visible' => false)).to include('_visible' => false)
        expect(prepared_for(_visible: false)).to include('_visible' => false)
      end

      it 'drops the default filter for nil' do
        expect(prepared_for('_visible' => nil).keys).not_to include('_visible')
      end

      ['true', 'false', 'yes', 0, 1].each do |bad|
        it "rejects #{bad.inspect} without echoing it" do
          expect { prepared_for('_visible' => bad) }
            .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue) do |error|
              expect(error.message).not_to include(bad.to_s)
            end
        end
      end

    end

    context 'select fields' do

      let(:value)       { 'CMS' }
      let(:option)      { instance_double('Option', _id: 42)}
      let(:options)     { instance_double('OptionRepository', by_name: option, :'locale=' => nil) }
      let(:field)       { instance_double('SelectField', name: 'category', persisted_name: 'category_id', select_options: options) }
      let(:_fields)     { instance_double('Fields', selects: [field], belongs_to: [], many_to_many: [], dates_and_date_times: [], numbers: [], booleans: []) }
      let(:conditions)  { { 'category' => value } }

      it { is_expected.to eq([{ '_visible' => true, 'content_type_id' => 1, 'category_id' => 42 }, nil]) }

      context 'an operator whose operand is not a field value' do
        let(:conditions) { { 'category.exists' => true } }

        it 'still maps the field to its persisted name' do
          expect(subject.first).to include('category_id.exists' => true)
        end
      end

    end

    context 'an _id list operand' do

      before { allow(adapter).to receive(:make_id) { |id| "id-#{id}" } }

      it 'converts every id in an Array' do
        expect(prepared_for('_id.in' => %w(a b))).to include('_id.in' => %w(id-a id-b))
      end

      it 'converts a Set the same way' do
        expect(prepared_for('_id.in' => Set['a'])).to include('_id.in' => %w(id-a))
      end

    end

    context 'select fields carrying a list or an unknown option' do

      let(:option)  { instance_double('Option', _id: 42) }
      let(:options) { instance_double('OptionRepository', :'locale=' => nil) }
      let(:field)   { instance_double('SelectField', name: 'category', persisted_name: 'category_id', select_options: options) }
      let(:_fields) { instance_double('Fields', selects: [field], belongs_to: [], many_to_many: [], dates_and_date_times: [], numbers: [], booleans: []) }

      before do
        allow(options).to receive(:by_name) { |name| name == 'CMS' ? option : nil }
      end

      it 'converts the elements of a list operand' do
        expect(prepared_for('category.in' => %w(CMS)))
          .to include('category_id.in' => [42])
      end

      it 'converts the elements of a Set operand' do
        expect(prepared_for('category.in' => Set['CMS']))
          .to include('category_id.in' => [42])
      end

      it 'leaves a non-field operand for its own kind to judge' do
        expect(prepared_for('category.exists' => /x/)).to include('category_id.exists' => /x/)
      end

      it 'maps an unknown option name to the unmatchable sentinel, not nil' do
        expect(prepared_for('category' => 'nope'))
          .to include('category_id' => Locomotive::Steam::Adapters::Query::Values.unmatchable)
      end

      it 'maps an unknown option name inside a list the same way' do
        expect(prepared_for('category.nin' => %w(CMS nope)))
          .to include('category_id.nin' => [42, Locomotive::Steam::Adapters::Query::Values.unmatchable])
      end

      it 'still resolves a nil operand to nil' do
        expect(prepared_for('category' => nil)).to include('category_id' => nil)
      end

    end

    context 'belongs_to fields' do

      let(:value)       { 42 }
      let(:field)       { instance_double('BelongsToField', name: 'person', persisted_name: 'person_id', target_id: '42') }
      let(:_fields)     { instance_double('Fields', selects: [], belongs_to: [field], many_to_many: [], dates_and_date_times: [], numbers: [], booleans: []) }
      let(:conditions)  { { 'person' => value } }

      it { is_expected.to eq([{ '_visible' => true, 'content_type_id' => 1, 'person_id' => 42 }, nil]) }

      context 'the target value is a content entry' do

        let(:value) { instance_double('TargetContentEntry', _id: 1) }

        it { is_expected.to eq([{ '_visible' => true, 'content_type_id' => 1, 'person_id' => 1 }, nil]) }

      end

      context 'the target is a hash' do

        let(:value) { { '_id' => 42 } }

        it { is_expected.to eq([{ '_visible' => true, 'content_type_id' => 1, 'person_id' => 42 }, nil]) }

      end

      context 'the target value is an arry of content entry' do

        let(:value) { [instance_double('TargetContentEntry', _id: 1), instance_double('TargetContentEntry', _id: 2)] }
        let(:conditions)  { { 'person.in' => value } }

        it { is_expected.to eq([{ '_visible' => true, 'content_type_id' => 1, 'person_id.in' => [1, 2] }, nil]) }

      end

      context 'testing a nil value (field => nil)' do

        let(:value) { nil }
        it { is_expected.to eq([{ '_visible' => true, 'content_type_id' => 1, 'person_id' => nil }, nil]) }

      end

      context 'testing a nil value (field.ne => nil)' do

        let(:conditions)  { { 'person.ne' => nil } }
        it { is_expected.to eq([{ '_visible' => true, 'content_type_id' => 1, 'person_id.ne' => nil }, nil]) }

      end

    end

    context 'many_to_many fields' do

      let(:value)       { 42 }
      let(:field)       { instance_double('ManyToManyField', name: 'tags', persisted_name: 'tag_ids', target_id: '42') }
      let(:_fields)     { instance_double('Fields', selects: [], belongs_to: [], many_to_many: [field], dates_and_date_times: [], numbers: [], booleans: []) }
      let(:conditions)  { { 'tags.in' => value } }

      it { is_expected.to eq([{ '_visible' => true, 'content_type_id' => 1, 'tag_ids.in' => [42] }, nil]) }

      context 'the documented all form, once the parser has normalized it' do

        let(:target_fields) do
          instance_double('Fields', selects: [], belongs_to: [], many_to_many: [],
                                    dates_and_date_times: [], numbers: [], booleans: [])
        end
        let(:target_type) do
          build_content_type('Tags', _id: 9, order_by: '_position', fields: target_fields, label_field_name: :name)
        end
        let(:entries) do
          [{ content_type_id: 9, _position: 0, _slug: { en: 'A' } },
           { content_type_id: 9, _position: 1, _slug: { en: 'B' } }]
        end
        let(:conditions) { { 'tags.all' => %w(A B) } }

        before { allow(content_type_repository).to receive(:find).with('42').and_return(target_type) }

        # Filesystem entries use their slugs as IDs.
        it 'resolves every element as a slug under the persisted name' do
          expect(subject.first).to include('tag_ids.all' => %w(A B))
        end

        context 'with an element no slug holds' do

          let(:conditions) { { 'tags.all' => %w(A C) } }

          it 'marks the unresolved element as unmatchable' do
            expect(subject.first['tag_ids.all'])
              .to eq ['A', Locomotive::Steam::Adapters::Query::Values.unmatchable]
          end

        end

      end

      context 'the target value is a content entry' do

        let(:value) { [instance_double('TargetContentEntry', _id: 1), 42] }

        it { is_expected.to eq([{ '_visible' => true, 'content_type_id' => 1, 'tag_ids.in' => [1, 42] }, nil]) }

      end

    end

  end

end
