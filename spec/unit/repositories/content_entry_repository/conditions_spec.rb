require 'spec_helper'

require_relative '../../../support/content_entry_repository_context'

describe Locomotive::Steam::ContentEntryRepository do

  include_context 'content entry repository'

  describe '#query_parts' do

    let(:conditions) { {} }

    subject { repository.with(type).send(:query_parts, conditions) }

    let(:prepared) { combined_conditions(subject.first) }

    def combined_conditions(clauses)
      clauses.reduce({}, :merge)
    end

    def prepared_for(conditions)
      combined_conditions(repository.with(type).send(:query_parts, conditions).first)
    end

    describe 'clause composition' do

      it 'starts from the scope clause and the default visibility clause' do
        expect(subject.first).to eq [{ 'content_type_id' => 1 }, { '_visible' => true }]
      end

      it 'keeps a caller bound apart from the scope bound' do
        clauses, _ = repository.with(type).send(:query_parts, 'content_type_id' => 99)

        expect(clauses).to include({ 'content_type_id' => 99 }, { 'content_type_id' => 1 })
      end

      it 'keeps contradicting visibility criteria as two clauses' do
        repo = repository.with(type)
        repo.send(:association_conditions=, '_visible' => true)

        clauses, _ = repo.send(:query_parts, '_visible' => false)

        expect(clauses).to include({ '_visible' => false }, { '_visible' => true })
      end

      context 'a typed field in the association caller criteria' do

        let(:field)   { instance_double('NumberField', name: 'score', persisted_name: 'score', type: :integer) }
        let(:_fields) { instance_double('Fields', selects: [], belongs_to: [], many_to_many: [], dates_and_date_times: [], numbers: [field], booleans: []) }

        it 'field-normalizes them like any caller input' do
          repo = repository.with(type)
          repo.send(:association_conditions=, 'score' => '12')

          clauses, _ = repo.send(:query_parts, {})

          expect(clauses).to include('score' => 12)
        end

      end

      it 'keeps association caller criteria apart from the association bound' do
        repo = repository.with(type)
        repo.local_conditions['_id.in'] = %w(article-a)
        repo.send(:association_conditions=, '_id.in' => %w(article-b))

        clauses, _ = repo.send(:query_parts, {})

        expect(clauses).to include({ '_id.in' => %w(article-b) })
        expect(clauses).to include(a_hash_including('_id.in' => %w(article-a)))
      end

      context 'the local scope carries a default order' do

        before { repository.local_conditions[:order_by] = 'name asc' }

        it 'the caller order wins' do
          _, order_by = repository.with(type).send(:query_parts, order_by: 'score desc')

          expect(order_by).to eq 'score desc'
        end

        it 'the local order stands without a caller order' do
          _, order_by = repository.with(type).send(:query_parts, {})

          expect(order_by).to eq 'name asc'
        end

      end

    end

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

      it { expect(prepared).to eq({ '_visible' => true, 'content_type_id' => 1, 'category_id' => 42 }) }

      context 'an operator whose operand is not a field value' do
        let(:conditions) { { 'category.exists' => true } }

        it 'still maps the field to its persisted name' do
          expect(prepared).to include('category_id.exists' => true)
        end
      end

    end

    context 'an _id list operand' do

      before { allow(adapter).to receive(:make_id) { |id| "id-#{id}" } }

      it 'converts every id in an Array' do
        expect(prepared_for('_id.in' => %w(a b))).to include('_id.in' => %w(id-a id-b))
      end

      context 'an id the adapter cannot read' do

        before { allow(adapter).to receive(:make_id) { false } }

        it 'reports the invalid id' do
          allow(Locomotive::Steam.configuration).to receive(:mode).and_return(:test)
          expect(Locomotive::Common::Logger).to receive(:warn).with(/"_id".*invalid_id/)

          prepared_for('_id' => 'nope')
        end

      end

    end

    context 'select fields carrying a list or an unknown option' do

      let(:option)  { instance_double('Option', _id: 42) }
      let(:options) { instance_double('OptionRepository', :'locale=' => nil) }
      let(:field)   { instance_double('SelectField', name: 'category', persisted_name: 'category_id', type: :select, select_options: options) }
      let(:_fields) { instance_double('Fields', selects: [field], belongs_to: [], many_to_many: [], dates_and_date_times: [], numbers: [], booleans: []) }

      before do
        allow(options).to receive(:by_name) { |name| name == 'CMS' ? option : nil }
      end

      it 'converts the elements of a list operand' do
        expect(prepared_for('category.in' => %w(CMS)))
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

      it 'reports the unknown option' do
        allow(Locomotive::Steam.configuration).to receive(:mode).and_return(:test)
        expect(Locomotive::Common::Logger).to receive(:warn).with(/"category".*unknown_select_option/)

        prepared_for('category' => 'nope')
      end

    end

    context 'belongs_to fields' do

      let(:value)       { 42 }
      let(:field)       { instance_double('BelongsToField', name: 'person', persisted_name: 'person_id', target_id: '42') }
      let(:_fields)     { instance_double('Fields', selects: [], belongs_to: [field], many_to_many: [], dates_and_date_times: [], numbers: [], booleans: []) }
      let(:conditions)  { { 'person' => value } }

      it { expect(prepared).to eq({ '_visible' => true, 'content_type_id' => 1, 'person_id' => 42 }) }

      context 'the target value is a content entry' do

        let(:value) { instance_double('TargetContentEntry', _id: 1) }

        it { expect(prepared).to eq({ '_visible' => true, 'content_type_id' => 1, 'person_id' => 1 }) }

      end

      context 'the target is a hash' do

        let(:value) { { '_id' => 42 } }

        it { expect(prepared).to eq({ '_visible' => true, 'content_type_id' => 1, 'person_id' => 42 }) }

      end

      context 'the target value is an arry of content entry' do

        let(:value) { [instance_double('TargetContentEntry', _id: 1), instance_double('TargetContentEntry', _id: 2)] }
        let(:conditions)  { { 'person.in' => value } }

        it { expect(prepared).to eq({ '_visible' => true, 'content_type_id' => 1, 'person_id.in' => [1, 2] }) }

      end

      context 'testing a nil value (field => nil)' do

        let(:value) { nil }
        it { expect(prepared).to eq({ '_visible' => true, 'content_type_id' => 1, 'person_id' => nil }) }

      end

      context 'testing a nil value (field.ne => nil)' do

        let(:conditions)  { { 'person.ne' => nil } }
        it { expect(prepared).to eq({ '_visible' => true, 'content_type_id' => 1, 'person_id.ne' => nil }) }

      end

    end

    context 'many_to_many fields' do

      let(:value)       { 42 }
      let(:field)       { instance_double('ManyToManyField', name: 'tags', persisted_name: 'tag_ids', type: :many_to_many, target_id: '42') }
      let(:_fields)     { instance_double('Fields', selects: [], belongs_to: [], many_to_many: [field], dates_and_date_times: [], numbers: [], booleans: []) }
      let(:conditions)  { { 'tags.in' => value } }

      it { expect(prepared).to eq({ '_visible' => true, 'content_type_id' => 1, 'tag_ids.in' => [42] }) }

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
          expect(prepared).to include('tag_ids.all' => %w(A B))
        end

        context 'with an element no slug holds' do

          let(:conditions) { { 'tags.all' => %w(A C) } }

          it 'marks the unresolved element as unmatchable' do
            expect(prepared['tag_ids.all'])
              .to eq ['A', Locomotive::Steam::Adapters::Query::Values.unmatchable]
          end

          it 'reports the unresolved slug' do
            allow(Locomotive::Steam.configuration).to receive(:mode).and_return(:test)
            expect(Locomotive::Common::Logger).to receive(:warn).with(/"tags".*unknown_slug/)

            subject
          end

        end

      end

      context 'the target value is a content entry' do

        let(:value) { [instance_double('TargetContentEntry', _id: 1), 42] }

        it { expect(prepared).to eq({ '_visible' => true, 'content_type_id' => 1, 'tag_ids.in' => [1, 42] }) }

      end

    end

  end

end
