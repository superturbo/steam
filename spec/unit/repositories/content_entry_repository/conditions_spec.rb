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

    describe 'a field and its persisted name' do

      let(:field) do
        instance_double('BelongsToField', name: 'maker', persisted_name: 'maker_id',
                        type: :belongs_to, target_id: '42')
      end
      let(:type) do
        build_content_type('Articles', label_field_name: :title,
                           fields_by_name: { maker: field }, fields_with_default: [])
      end

      it 'refuses both names in one source, whatever the order' do
        [{ 'maker' => 'maker-one', 'maker_id' => 'zzz' },
         { 'maker_id' => 'zzz', 'maker' => 'maker-one' }].each do |conditions|
          expect { prepared_for(conditions) }
            .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue, /maker/)
        end
      end

      it 'keeps an equality and a suffixed operator apart' do
        expect { prepared_for('maker' => nil, 'maker_id.eq' => 'zzz') }
          .not_to raise_error
      end

      it 'keeps different operators on one persisted name apart' do
        clauses, _ = repository.with(type).send(:query_parts, 'maker.ne' => nil, 'maker_id.eq' => 'zzz')

        expect(combined_conditions(clauses)).to include('maker_id.ne' => nil, 'maker_id.eq' => 'zzz')
      end

    end

    describe 'a name owned by two fields' do

      let(:field) do
        instance_double('BelongsToField', name: 'maker', persisted_name: 'maker_id',
                        type: :belongs_to, target_id: '42')
      end
      let(:extra) do
        instance_double('StringField', name: 'maker_id', persisted_name: 'maker_id', type: :string)
      end
      let(:type) do
        build_content_type('Articles', label_field_name: :title,
                           fields_by_name: { maker: field, maker_id: extra },
                           invalid_entry_names: %w(maker maker_id position_in_maker),
                           fields_with_default: [])
      end

      it 'refuses the shared name' do
        expect { prepared_for('maker_id' => 'zzz') }
          .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue, "maker_id belongs to a field with conflicting entry names")
      end

      it 'refuses the shared name under any operator' do
        expect { prepared_for('maker_id.ne' => 'zzz') }
          .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue, "maker_id belongs to a field with conflicting entry names")
      end

      it 'refuses every name of the colliding group' do
        %w(maker position_in_maker).each do |name|
          expect { prepared_for(name => nil) }
            .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue,
                            "#{name} belongs to a field with conflicting entry names")
        end
      end

      it 'refuses to order by any name of the colliding group' do
        %w(maker maker_id position_in_maker).each do |name|
          expect { repository.with(type).all(order_by: name) }
            .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue, "#{name} belongs to a field with conflicting entry names")
        end
      end

      context 'the primary key name is contested' do

        let(:type) do
          build_content_type('Articles', label_field_name: :title,
                             invalid_entry_names: %w(_id), fields_with_default: [])
        end

        it 'refuses it like any other name' do
          expect { prepared_for('_id' => '42') }
            .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue, "_id belongs to a field with conflicting entry names")
        end

      end

    end

    describe 'a field with no queryable persisted value' do

      let(:field)  { instance_double('HasManyField', name: 'articles', persisted_name: nil, type: :has_many) }
      let(:secret) { instance_double('PasswordField', name: 'secret', persisted_name: nil, type: :password) }
      let(:type) do
        build_content_type('Articles', label_field_name: :title,
                           fields_by_name: { articles: field, secret: secret },
                           unqueryable_field_names: %w(articles secret secret_hash secret_confirmation),
                           fields_with_default: [])
      end

      { 'articles' => 'x', 'articles.ne' => 'x', 'articles.gt' => 'x',
        'articles.exists' => true, 'articles.size' => 3, 'secret' => 'x',
        'secret_hash.exists' => true, 'secret_confirmation' => 'x' }.each do |key, operand|
        it "refuses the #{key} criterion" do
          name = key.split('.').first

          expect { prepared_for(key => operand) }
            .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue, /#{name} is not queryable/)
        end
      end

      it 'keeps a name the schema does not know at all' do
        expect(prepared_for('foobar' => 'x')).to include('foobar' => 'x')
      end

    end

    describe 'a persisted name criterion' do

      let(:field) do
        instance_double('BelongsToField', name: 'maker', persisted_name: 'maker_id',
                        type: :belongs_to, target_id: '42')
      end
      let(:list_field) do
        instance_double('ManyToManyField', name: 'topics', persisted_name: 'topic_ids',
                        type: :many_to_many, target_id: '43')
      end
      let(:type) do
        build_content_type('Articles', label_field_name: :title,
                           fields_by_name: { maker: field, topics: list_field },
                           fields_by_persisted_name: { 'maker_id' => field, 'topic_ids' => list_field },
                           fields_with_default: [])
      end

      it 'keeps nil semantics' do
        expect(prepared_for('maker_id' => nil)).to include('maker_id' => nil)
      end

      it 'reads the operand as an id, never a slug' do
        expect(prepared_for('maker_id' => '42')).to include('maker_id' => '42')
      end

      it 'reads a symbol as the text form of an id' do
        expect(prepared_for('maker_id' => :'42')).to include('maker_id' => '42')
      end

      it 'reads list elements as ids, keeping a null element' do
        expect(prepared_for('topic_ids.in' => [nil, '42'])).to include('topic_ids.in' => [nil, '42'])
      end

      it 'leaves exists to its own kind' do
        expect(prepared_for('maker_id.exists' => true)).to include('maker_id.exists' => true)
      end

      it 'refuses an Array with eq or ne' do
        [{ 'topic_ids' => %w(a b) }, { 'maker_id.ne' => %w(a) }].each do |conditions|
          expect { prepared_for(conditions) }
            .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue,
                            /takes one value with eq or ne/)
        end
      end

      it 'takes a flat list of ids, not stored fragments' do
        [{ 'topic_ids.in' => [%w(a b)] }, { 'topic_ids.all' => [%w(a b)] }].each do |conditions|
          expect { prepared_for(conditions) }
            .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue, /flat list of ids/)
        end
      end

      it 'refuses an ordering comparison, a Range and a Regexp' do
        [{ 'maker_id.gt' => 'x' }, { 'maker_id' => 1..10 }, { 'maker_id' => /abc/ },
         { 'topic_ids.in' => [/abc/] }].each do |conditions|
          expect { prepared_for(conditions) }
            .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue, /matched by id/)
        end
      end

    end

    describe 'the liquid surface' do

      let(:field) do
        instance_double('BelongsToField', name: 'maker', persisted_name: 'maker_id',
                        type: :belongs_to, target_id: '42')
      end
      let(:type) do
        build_content_type('Articles', label_field_name: :title,
                           fields_by_name: { maker: field },
                           fields_by_persisted_name: { 'maker_id' => field },
                           fields_with_default: [])
      end

      def liquid_prepared(conditions)
        source = Locomotive::Steam::LiquidCriteria.wrap(conditions)

        combined_conditions(repository.with(type).send(:query_parts, source).first)
      end

      it 'keeps a declared field and the public system names' do
        expect(liquid_prepared('maker' => nil, '_slug' => 'x', 'created_at.exists' => true,
                               '_visible' => false, '_position.lt' => 5))
          .to include('maker_id' => nil, '_slug' => 'x', 'created_at.exists' => true,
                      '_position.lt' => 5)
      end

      it 'keeps order_by for the ordering stage' do
        source = Locomotive::Steam::LiquidCriteria.wrap('order_by' => 'title.asc')

        _, order_by = repository.with(type).send(:query_parts, source)

        expect(order_by).to eq 'title.asc'
      end

      # SEO names read from Liquid but do not filter.
      %w(maker_id content_type_id site_id unknown_field _label
         seo_title meta_description meta_keywords _translated).each do |name|
        it "refuses #{name}" do
          expect { liquid_prepared(name => 'x') }
            .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue,
                            /#{name} cannot filter entries of articles/)
        end
      end

      it 'refuses order_by under an operator' do
        expect { liquid_prepared('order_by.gt' => 'title') }
          .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue,
                          /order_by cannot filter entries of articles/)
      end

      it 'leaves the ruby surface permissive' do
        expect(prepared_for('maker_id' => '42')).to include('maker_id' => '42')
      end

    end

    context 'boolean fields' do

      let(:field)   { instance_double('BooleanField', name: 'flag', persisted_name: 'flag', type: :boolean) }
      let(:_fields) { instance_double('Fields', selects: [], belongs_to: [], many_to_many: [], dates_and_date_times: [], numbers: [], booleans: [field]) }

      it 'refuses a Range directly or inside an Array' do
        [{ 'flag' => 1..5 }, { 'flag' => [true, 1..5] }].each do |conditions|
          expect { prepared_for(conditions) }
            .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue, /expected a boolean/)
        end
      end

      it 'keeps a scalar comparison operand' do
        expect(prepared_for('flag.gte' => 'false')).to include('flag.gte' => false)
      end

    end

    describe 'two bounds on one field' do

      let(:field)   { instance_double('NumberField', name: 'price', persisted_name: 'price', type: :float) }
      let(:type) do
        build_content_type('Articles', label_field_name: :title,
                           fields_by_name: { price: field }, fields_with_default: [])
      end

      it 'reach the store as two separate clauses' do
        clauses, _ = repository.with(type).send(:query_parts, 'price.gte' => 1, 'price.lte' => 9)

        expect(clauses).to include({ 'price.gte' => 1.0 }, { 'price.lte' => 9.0 })
      end

    end

    describe 'a raw Mongo operator' do

      let(:field)   { instance_double('NumberField', name: 'score', persisted_name: 'score', type: :integer) }
      let(:_fields) { instance_double('Fields', selects: [], belongs_to: [], many_to_many: [], dates_and_date_times: [], numbers: [field], booleans: []) }

      it 'is rejected before the field grammar reads the operand' do
        expect { prepared_for('score' => { '$gt' => 5 }) }
          .to raise_error(Locomotive::Steam::Adapters::Query::UnsupportedOperator)
      end

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
        repo.send(:association_condition_sources=, ['_visible' => true])

        clauses, _ = repo.send(:query_parts, '_visible' => false)

        expect(clauses).to include({ '_visible' => false }, { '_visible' => true })
      end

      context 'a typed field in the association caller criteria' do

        let(:field)   { instance_double('NumberField', name: 'score', persisted_name: 'score', type: :integer) }
        let(:_fields) { instance_double('Fields', selects: [], belongs_to: [], many_to_many: [], dates_and_date_times: [], numbers: [field], booleans: []) }

        it 'field-normalizes them like any caller input' do
          repo = repository.with(type)
          repo.send(:association_condition_sources=, ['score' => '12'])

          clauses, _ = repo.send(:query_parts, {})

          expect(clauses).to include('score' => 12)
        end

      end

      it 'keeps association caller criteria apart from the association bound' do
        repo = repository.with(type)
        repo.local_conditions['_id.in'] = %w(article-a)
        repo.send(:association_condition_sources=, ['_id.in' => %w(article-b)])

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

      { '_visible.eq' => true, '_visible.ne' => true,
        '_visible.exists' => true, '_visible.in' => [true] }.each do |key, operand|
        it "rejects the #{key} criterion" do
          expect { prepared_for(key => operand) }
            .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue, /operator/)
        end
      end

      it 'rejects an operator without echoing the operand' do
        expect { prepared_for('_visible.ne' => 'junk') }
          .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue) do |error|
            expect(error.message).not_to include('junk')
          end
      end

      it 'rejects an operator in the scope clause' do
        repo = repository.with(type)
        repo.local_conditions['_visible.ne'] = true

        expect { repo.send(:query_parts, {}) }
          .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue, /operator/)
      end

      it 'rejects an operator in the association criteria' do
        repo = repository.with(type)
        repo.send(:association_condition_sources=, ['_visible.ne' => true])

        expect { repo.send(:query_parts, {}) }
          .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue, /operator/)
      end

      it 'keeps an operator on a name that only shares the prefix' do
        expect(prepared_for('_visible_state.ne' => true))
          .to include('_visible_state.ne' => true)
      end

    end

    context 'select fields' do

      let(:value)       { 'CMS' }
      let(:option)      { instance_double('Option', _id: 42)}
      let(:options)     { instance_double('OptionRepository', by_name: option, :'locale=' => nil) }
      let(:field)       { instance_double('SelectField', name: 'category', persisted_name: 'category_id', type: :select, select_options: options) }
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

      it 'refuses a nested list' do
        expect { prepared_for('_id.in' => [%w(a b)]) }
          .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue, '_id takes a flat list')
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

      it 'refuses a nested list' do
        expect { prepared_for('category.in' => [%w(CMS)]) }
          .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue, 'category takes a flat list')
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
      let(:field)       { instance_double('BelongsToField', name: 'person', persisted_name: 'person_id', type: :belongs_to, target_id: '42') }
      let(:_fields)     { instance_double('Fields', selects: [], belongs_to: [field], many_to_many: [], dates_and_date_times: [], numbers: [], booleans: []) }
      let(:conditions)  { { 'person' => value } }

      it { expect(prepared).to eq({ '_visible' => true, 'content_type_id' => 1, 'person_id' => 42 }) }

      it 'refuses a nested list under a list operator' do
        expect { prepared_for('person.in' => [[42]]) }
          .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue, 'person takes a flat list')
      end

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

      context 'the operand forms' do

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

        before { allow(content_type_repository).to receive(:find).with('42').and_return(target_type) }

        context 'eq and ne' do

          it 'reads a lone slug as the element the list must hold' do
            expect(prepared_for('tags' => 'A')).to include('tag_ids' => 'A')
          end

          it 'reads a lone slug under ne as the element the list must lack' do
            expect(prepared_for('tags.ne' => 'A')).to include('tag_ids.ne' => 'A')
          end

          it 'reads eq like the bare equality' do
            expect(prepared_for('tags.eq' => 'A')).to include('tag_ids.eq' => 'A')
          end

          it 'reads an id document as the same membership element' do
            expect(prepared_for('tags' => { '_id' => 42 })).to include('tag_ids' => 42)
          end

          it 'reads an entry as the same membership element' do
            entry = instance_double('TagEntry', _id: 42)

            expect(prepared_for('tags' => entry)).to include('tag_ids' => 42)
          end

          it 'keeps nil untouched' do
            expect(prepared_for('tags' => nil)).to include('tag_ids' => nil)
          end

          it 'reads a composite id entry as a membership list over its components' do
            entry = instance_double('TagEntry', _id: [42, 'comp'])

            expect(prepared_for('tags' => entry)).to include('tag_ids.in' => [42, 'comp'])
          end

          it 'reads a composite id under eq like the bare equality' do
            entry = instance_double('TagEntry', _id: [42, 'comp'])

            expect(prepared_for('tags.eq' => entry)).to include('tag_ids.in' => [42, 'comp'])
          end

          it 'reads a composite id under ne as the components the list must lack' do
            entry = instance_double('TagEntry', _id: [42, 'comp'])

            expect(prepared_for('tags.ne' => entry)).to include('tag_ids.nin' => [42, 'comp'])
          end

          it 'reads a composite id document the same way' do
            expect(prepared_for('tags' => { '_id' => [42, 'comp'] }))
              .to include('tag_ids.in' => [42, 'comp'])
          end

          it 'refuses an array operand' do
            [{ 'tags' => %w(A) }, { 'tags.eq' => %w(A) }, { 'tags.ne' => %w(A) }].each do |conditions|
              expect { prepared_for(conditions) }
                .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue,
                                /tags takes one value with eq or ne/)
            end
          end

        end

        context 'list operators' do

          it 'reads an id document as one element of the list' do
            expect(prepared_for('tags.in' => { '_id' => 42 })).to include('tag_ids.in' => [42])
          end

          it 'reads an id document under nin the same way' do
            expect(prepared_for('tags.nin' => { '_id' => 42 })).to include('tag_ids.nin' => [42])
          end

          it 'reads an id document under all the same way' do
            expect(prepared_for('tags.all' => { '_id' => 42 })).to include('tag_ids.all' => [42])
          end

          it 'expands a composite id entry into its components under in' do
            entry = instance_double('TagEntry', _id: [42, 'comp'])

            expect(prepared_for('tags.in' => ['A', entry]))
              .to include('tag_ids.in' => ['A', 42, 'comp'])
          end

          it 'expands a composite id entry into its components under nin' do
            entry = instance_double('TagEntry', _id: [42, 'comp'])

            expect(prepared_for('tags.nin' => entry)).to include('tag_ids.nin' => [42, 'comp'])
          end

          it 'refuses a composite id entry under all' do
            entry = instance_double('TagEntry', _id: [42, 'comp'])

            expect { prepared_for('tags.all' => [entry]) }
              .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue,
                              /tags does not accept a composite identity with all/)
          end

          it 'rejects the form before resolving any slug' do
            entry = instance_double('TagEntry', _id: [42, 'comp'])

            expect { prepared_for('tags.all' => ['A', entry]) }
              .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)

            expect(content_type_repository).not_to have_received(:find)
          end

          it 'refuses a nested list before resolving any slug' do
            %w(in nin all).each do |operator|
              expect { prepared_for("tags.#{operator}" => [%w(A B)]) }
                .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue, 'tags takes a flat list')
            end

            expect(content_type_repository).not_to have_received(:find)
          end

          it 'reads a nested list under equality as one value too many' do
            expect { prepared_for('tags' => [%w(A B)]) }
              .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue, 'tags takes one value with eq or ne')
          end

          it 'keeps a composite id document as one identity in the list' do
            expect(prepared_for('tags.in' => [{ '_id' => [42, 'comp'] }]))
              .to include('tag_ids.in' => [42, 'comp'])
          end

        end

        context 'all' do

          let(:conditions) { { 'tags.all' => %w(A B) } }

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

          describe 'resolution within one render' do

            def counted_lookups
              lookups = 0
              allow(adapter).to receive(:collection) { lookups += 1; loaded(entries) }

              yield

              lookups
            end

            it 'answers a repeated slug operand from its first lookup' do
              lookups = counted_lookups do
                2.times { expect(prepared_for('tags.all' => %w(A))).to include('tag_ids.all' => %w(A)) }
              end

              expect(lookups).to eq 1
              expect(content_type_repository).to have_received(:find).with('42').once
            end

            it 'answers a repeated unknown slug from its first lookup and still reports it' do
              allow(Locomotive::Steam.configuration).to receive(:mode).and_return(:test)
              expect(Locomotive::Common::Logger).to receive(:warn).with(/"tags".*unknown_slug/).twice

              lookups = counted_lookups do
                2.times do
                  expect(prepared_for('tags.all' => %w(C)).fetch('tag_ids.all'))
                    .to eq [Locomotive::Steam::Adapters::Query::Values.unmatchable]
                end
              end

              expect(lookups).to eq 1
            end

            it 'looks every distinct slug up on its own' do
              lookups = counted_lookups do
                prepared_for('tags.all' => %w(A))
                prepared_for('tags.all' => %w(B))
              end

              expect(lookups).to eq 2
            end

            context 'across locales' do

              let(:entries) do
                [{ content_type_id: 9, _position: 0, _slug: { en: 'A', fr: 'A' } },
                 { content_type_id: 9, _position: 1, _slug: { en: 'B', fr: 'B' } }]
              end

              it 'looks the same slug up once per locale' do
                lookups = counted_lookups do
                  prepared_for('tags.all' => %w(A))
                  repository.locale = :fr
                  prepared_for('tags.all' => %w(A))
                end

                expect(lookups).to eq 2
              end

            end

            context 'a second association aiming at another target' do

              let(:other_field) do
                instance_double('OtherManyToManyField', name: 'labels', persisted_name: 'label_ids',
                                type: :many_to_many, target_id: '43')
              end
              let(:_fields) do
                instance_double('Fields', selects: [], belongs_to: [], many_to_many: [field, other_field],
                                          dates_and_date_times: [], numbers: [], booleans: [])
              end
              let(:other_target_type) do
                build_content_type('Labels', _id: 10, order_by: '_position', fields: target_fields, label_field_name: :name)
              end

              before { allow(content_type_repository).to receive(:find).with('43').and_return(other_target_type) }

              it 'keeps the resolutions of the two targets apart' do
                lookups = counted_lookups do
                  prepared_for('tags.all' => %w(A))
                  prepared_for('labels.all' => %w(A))
                end

                expect(lookups).to eq 2
              end

            end

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
