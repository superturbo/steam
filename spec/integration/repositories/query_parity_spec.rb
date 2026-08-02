require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'
require_relative '../../support/adapter_parity_fixture'

# Fixed expected rows catch query bugs shared by both adapters.
describe 'Query parity' do

  CASES = [
    { desc: 'a scalar equals an array field element',
      conditions: { labels: 'x' }, expected: %w(arrays embedded) },

    { desc: 'an embedded document matches in key order',
      conditions: { payload: { 'b' => 2, 'a' => 1 } }, expected: %w(embedded) },

    { desc: 'an embedded document does not match reordered',
      conditions: { payload: { 'a' => 1, 'b' => 2 } }, expected: [] },

    { desc: 'equality on a boolean field',
      conditions: { flag: false }, expected: %w(arrays embedded zero) },

    { desc: 'equality on a select field resolves the option name',
      conditions: { category: 'alpha' }, expected: %w(scalars) },

    { desc: 'gt on a numeric field',
      conditions: { 'score.gt' => 5 }, expected: %w(arrays) },

    { desc: 'in on a select field resolves every option name',
      conditions: { 'category.in' => %w(alpha beta) }, expected: %w(arrays scalars) },

    { desc: 'all on a select field resolves the option name',
      conditions: { 'category.all' => %w(alpha) }, expected: %w(scalars) },

    { desc: 'nin on a select field excludes only the named options',
      conditions: { 'category.nin' => %w(alpha) },
      expected: %w(all-missing arrays embedded explicit-nils zero) },

    # 0 is not an option name, but it is a stored option id on Filesystem
    { desc: 'an unresolved select name cannot collide with a stored option id',
      conditions: { category: 0 }, expected: [] },

    { desc: 'scalar equality on a string field',
      conditions: { name: 'Scalars' }, expected: %w(scalars) },

    { desc: 'ne on a string field',
      conditions: { 'name.ne' => 'Scalars' },
      expected: %w(all-missing arrays embedded explicit-nils zero) },

    { desc: 'in on a string field',
      conditions: { 'name.in' => ['Scalars', 'Zero'] }, expected: %w(scalars zero) },

    { desc: 'a Regexp on a plain field',
      conditions: { name: /Scal/ }, expected: %w(scalars) },

    { desc: 'a Regexp against a non-string field matches nothing',
      conditions: { score: /5/ }, expected: [] },

    { desc: 'a Range on a plain field matches its bounds',
      conditions: { score: (5..6) }, expected: %w(embedded scalars) },

    { desc: 'in matching an array field element',
      conditions: { 'labels.in' => ['x'] }, expected: %w(arrays embedded) },

    { desc: 'all against an array field',
      conditions: { 'labels.all' => %w(x y) }, expected: %w(arrays) },

    { desc: 'an empty all matches nothing',
      conditions: { 'labels.all' => [] }, expected: [] },

    { desc: 'an array value matches a single-level array exactly',
      conditions: { labels: %w(y x z) }, expected: %w(arrays) },

    { desc: 'an array value must match exactly, not intersect',
      conditions: { labels: ['x'] }, expected: %w(embedded) },

    { desc: 'a reordered array value matches nothing',
      conditions: { labels: %w(x y z) }, expected: [] },

    { desc: 'a Set value is normalized to an array',
      conditions: { labels: Set['y', 'x', 'z'] }, expected: %w(arrays) },

    { desc: 'all with a nested array operand matches the whole array field',
      conditions: { 'labels.all' => [%w(y x z)] }, expected: %w(arrays) },

    { desc: 'in with a nested array operand matches the whole array field',
      conditions: { 'labels.in' => [%w(y x z)] }, expected: %w(arrays) },

    { desc: 'size counts array elements',
      conditions: { 'labels.size' => 3 }, expected: %w(arrays) },

    { desc: 'gt matches an element of an array field',
      conditions: { 'labels.gt' => 'y' }, expected: %w(arrays) },

    # y meets the lower bound, x the upper, and no single element meets both
    { desc: 'a Range lets different elements of an array field satisfy each bound',
      conditions: { labels: ('y'..'x') }, expected: %w(arrays) },

    { desc: 'a Regexp matches an element of an array field',
      conditions: { labels: /^x$/ }, expected: %w(arrays embedded) },

    { desc: 'gte on a float field',
      conditions: { 'price.gte' => 5.5 }, expected: %w(arrays scalars) },

    { desc: 'gt on a float field',
      conditions: { 'price.gt' => 10 }, expected: %w(scalars) },

    { desc: 'a numeric condition given as a String, the way params arrive',
      conditions: { 'score.gt' => '5' }, expected: %w(arrays) },

    { desc: 'a numeric String read through surrounding whitespace',
      conditions: { 'score.gt' => ' 5 ' }, expected: %w(arrays) },

    # Ruby would read these as 15 and 1.0; neither is a number here, and the
    # integer and float fields reach that answer through their own grammar.
    { desc: 'an underscored integer String is not a number',
      conditions: { 'score.gt' => '1_5' }, expected: [] },

    { desc: 'a hexadecimal String is not a number',
      conditions: { 'price.gt' => '0x1' }, expected: [] },

    # The decimal overflows Float and remains a non-numeric operand.
    { desc: 'a String that overflows to infinity is not a number either',
      conditions: { 'price.lt' => '1e9999' }, expected: [] },

    { desc: 'a numeric list operand given as Strings',
      conditions: { 'price.in' => %w(5.5 6) }, expected: %w(arrays) },

    # If coercion returned nil, every row without a score would match.
    { desc: 'an invalid numeric string does not gain nil semantics',
      conditions: { score: 'abc' }, expected: [] },

    { desc: 'gt against a nil operand matches nothing',
      conditions: { 'score.gt' => nil }, expected: [] },

    { desc: 'gte against a nil operand matches nothing',
      conditions: { 'score.gte' => nil }, expected: [] },

    { desc: 'lt against a nil operand matches nothing',
      conditions: { 'score.lt' => nil }, expected: [] },

    { desc: 'lte against a nil operand matches nothing',
      conditions: { 'score.lte' => nil }, expected: [] },

    # A field without value casting preserves the stored missing/null
    # distinction.
    { desc: 'eq nil matches a missing or null array field',
      conditions: { labels: nil },
      expected: %w(all-missing explicit-nils scalars zero) },

    { desc: 'ne nil matches only a present array field',
      conditions: { 'labels.ne' => nil }, expected: %w(arrays embedded) },

    { desc: 'in [nil] matches a missing or null array field',
      conditions: { 'labels.in' => [nil] },
      expected: %w(all-missing explicit-nils scalars zero) },

    { desc: 'nin [nil] excludes a missing or null array field',
      conditions: { 'labels.nin' => [nil] }, expected: %w(arrays embedded) },

    { desc: 'ne a non-null value also matches a missing field',
      conditions: { 'labels.ne' => 'x' },
      expected: %w(all-missing explicit-nils scalars zero) },

    { desc: 'nin [value] matches a missing field',
      conditions: { 'labels.nin' => ['x'] },
      expected: %w(all-missing explicit-nils scalars zero) },

    { desc: 'exists true on an array field',
      conditions: { 'labels.exists' => true },
      expected: %w(arrays embedded explicit-nils) },

    { desc: 'exists false on an array field',
      conditions: { 'labels.exists' => false },
      expected: %w(all-missing scalars zero) }
  ].freeze

  # Memory casts a present null integer to 0 before matching; MongoDB filters
  # raw BSON.
  INTEGER_NULL_CASES = [
    { desc: 'eq nil matches a missing or null field',
      conditions: { score: nil }, expected: %w(all-missing explicit-nils) },

    { desc: 'ne nil matches only present, non-null fields',
      conditions: { 'score.ne' => nil }, expected: %w(arrays embedded scalars zero) },

    { desc: 'in [nil] matches a missing or null field',
      conditions: { 'score.in' => [nil] }, expected: %w(all-missing explicit-nils) },

    { desc: 'nin [nil] excludes a missing or null field',
      conditions: { 'score.nin' => [nil] }, expected: %w(arrays embedded scalars zero) }
  ].freeze

  # A rejected input has to be rejected the same way everywhere, not merely
  # return different rows.
  ERROR_CASES = [
    { desc: 'a removed legacy operator (neq)',
      conditions: { 'name.neq' => 'Scalars' },
      error: Locomotive::Steam::Adapters::Query::UnsupportedOperator },

    { desc: 'a removed legacy operator (matches)',
      conditions: { 'name.matches' => 'Scal' },
      error: Locomotive::Steam::Adapters::Query::UnsupportedOperator },

    { desc: 'an unknown operator',
      conditions: { 'name.bogus' => 'x' },
      error: Locomotive::Steam::Adapters::Query::UnsupportedOperator },

    { desc: 'a nested field path',
      conditions: { 'address.location.ne' => 'x' },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'an empty field name',
      conditions: { '' => 'x' },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'an empty field with an operator suffix',
      conditions: { '.ne' => 'x' },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'a raw Mongo operator in a key',
      conditions: { '$where' => 'sleep(1000)' },
      error: Locomotive::Steam::Adapters::Query::UnsupportedOperator },

    { desc: 'a raw Mongo operator nested in a value',
      conditions: { 'name' => { '$ne' => 'Scalars' } },
      error: Locomotive::Steam::Adapters::Query::UnsupportedOperator },

    { desc: 'a raw Mongo operator inside an array value',
      conditions: { 'name' => [{ '$ne' => 'Scalars' }] },
      error: Locomotive::Steam::Adapters::Query::UnsupportedOperator },

    { desc: 'a structural comparison operand',
      conditions: { 'score.gt' => [1] },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'a boolean comparison operand',
      conditions: { 'score.gt' => true },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    # Typed integers outside BSON int64 and non-finite floats are invalid operands.
    { desc: 'an integer beyond int64',
      conditions: { 'score.gt' => 2**63 },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'a float that is not finite',
      conditions: { 'price.gt' => Float::INFINITY },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'an order_by criterion naming more than a field and a direction',
      conditions: { order_by: 'name asc desc' },
      error: Locomotive::Steam::Adapters::Query::InvalidValue }
  ].freeze

  shared_examples_for 'the query semantics' do

    let(:site)            { Locomotive::Steam::SiteRepository.new(adapter).by_handle_or_domain('adapter-parity', nil) }
    let(:type_repository) { Locomotive::Steam::ContentTypeRepository.new(adapter, site, AdapterParityFixture::LOCALE) }

    def slugs(conditions)
      repository = Locomotive::Steam::ContentEntryRepository.new(
        adapter, site, AdapterParityFixture::LOCALE, type_repository)

      repository.with(type_repository.by_slug('specimens')).all(conditions).map do |entry|
        entry._slug[AdapterParityFixture::LOCALE]
      end
    end

    CASES.each do |c|
      it(c[:desc]) { expect(slugs(c[:conditions])).to match_array(c[:expected]) }
    end

    ERROR_CASES.each do |c|
      it("rejects #{c[:desc]}") { expect { slugs(c[:conditions]) }.to raise_error(c[:error]) }
    end

    INTEGER_NULL_CASES.each do |c|
      it(c[:desc]) do
        pending 'Memory filters through the accessor, where nil.to_i is 0' if filesystem?
        expect(slugs(c[:conditions])).to match_array(c[:expected])
      end
    end

  end

  context 'MongoDB' do

    before(:all) { AdapterParityFixture.seed_mongodb! }
    after(:all)  { AdapterParityFixture.cleanup! }

    it_should_behave_like 'the query semantics' do
      let(:adapter) { AdapterParityFixture.mongodb_adapter }

      def filesystem?; false; end
    end

  end

  context 'Filesystem' do

    it_should_behave_like 'the query semantics' do
      let(:adapter) { AdapterParityFixture.filesystem_adapter }

      def filesystem?; true; end
    end

  end

end
