require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'
require_relative '../../support/adapter_parity_fixture'

# Fixed expected rows catch query bugs shared by both adapters.
describe 'Query parity' do

  TRANSPORT_MOMENT = Time.utc(2013, 2, 11, 23, 30).in_time_zone('Europe/Paris')

  CASES = [
    { desc: 'a scalar equals an array field element',
      conditions: { labels: 'x' }, expected: %w(arrays embedded) },

    { desc: 'an embedded document matches in key order',
      conditions: { payload: { 'b' => 2, 'a' => 1 } }, expected: %w(embedded) },

    { desc: 'an embedded document does not match reordered',
      conditions: { payload: { 'a' => 1, 'b' => 2 } }, expected: [] },

    { desc: 'equality on a boolean field',
      conditions: { flag: false }, expected: %w(arrays embedded zero) },

    { desc: 'a boolean written the way a form sends it',
      conditions: { flag: '1' }, expected: %w(scalars) },

    { desc: 'a boolean the grammar cannot read matches nothing',
      conditions: { flag: 'yes' }, expected: [] },

    { desc: 'a date written with the slash form the documentation spells',
      conditions: { 'held_on.lte' => '2020/01/01' }, expected: %w(arrays scalars) },

    { desc: 'a date the grammar cannot read matches nothing',
      conditions: { 'held_on.lte' => 'tomorrow' }, expected: [] },

    { desc: 'gt treats true as greater than false',
      conditions: { 'flag.gt' => false }, expected: %w(scalars) },

    { desc: 'gte on a boolean matches both values',
      conditions: { 'flag.gte' => false }, expected: %w(arrays embedded scalars zero) },

    { desc: 'lt on a boolean excludes missing and null fields',
      conditions: { 'flag.lt' => true }, expected: %w(arrays embedded zero) },

    { desc: 'a Symbol names the same value as the string it spells',
      conditions: { name: :Scalars }, expected: %w(scalars) },

    { desc: 'a Symbol inside a list names it too',
      conditions: { 'name.in' => [:Scalars] }, expected: %w(scalars) },

    { desc: 'ne against a Symbol excludes what eq would have matched',
      conditions: { 'name.ne' => :Scalars },
      expected: %w(all-missing arrays embedded explicit-nils zero) },

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

    { desc: 'an unresolved option matches nothing as a plain field',
      conditions: { category: 'nope' }, expected: [] },

    { desc: 'ne with an unresolved option matches everything',
      conditions: { 'category.ne' => 'nope' },
      expected: %w(all-missing arrays embedded explicit-nils scalars zero) },

    { desc: 'in drops an unresolved option and keeps the rest',
      conditions: { 'category.in' => %w(alpha nope) }, expected: %w(scalars) },

    { desc: 'nin drops it too, excluding only what resolved',
      conditions: { 'category.nin' => %w(alpha nope) },
      expected: %w(all-missing arrays embedded explicit-nils zero) },

    { desc: 'all with an unresolved option matches nothing',
      conditions: { 'category.all' => %w(alpha nope) }, expected: [] },

    { desc: 'in with only an unresolved option matches nothing',
      conditions: { 'category.in' => %w(nope) }, expected: [] },

    { desc: 'nin with only an unresolved option excludes nothing',
      conditions: { 'category.nin' => %w(nope) },
      expected: %w(all-missing arrays embedded explicit-nils scalars zero) },

    { desc: 'an id absent from both stores matches nothing',
      conditions: { _id: 'not-an-objectid' }, expected: [] },

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

    # The decimal overflows Float and therefore matches nothing.
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

    { desc: 'eq nil matches a missing or null integer field',
      conditions: { score: nil }, expected: %w(all-missing explicit-nils) },

    { desc: 'ne nil matches only a present, non-null integer field',
      conditions: { 'score.ne' => nil }, expected: %w(arrays embedded scalars zero) },

    { desc: 'in [nil] matches a missing or null integer field',
      conditions: { 'score.in' => [nil] }, expected: %w(all-missing explicit-nils) },

    { desc: 'nin [nil] excludes a missing or null integer field',
      conditions: { 'score.nin' => [nil] }, expected: %w(arrays embedded scalars zero) },

    { desc: 'eq nil matches a missing float field',
      conditions: { price: nil },
      expected: %w(all-missing embedded explicit-nils zero) },

    { desc: 'ne nil matches only a present float field',
      conditions: { 'price.ne' => nil }, expected: %w(arrays scalars) },

    # Untyped fields exercise the same missing/null semantics without entity casting.
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
      expected: %w(all-missing scalars zero) },

    { desc: "a moment matches the date in the site's timezone",
      conditions: { held_on: DateTime.new(2013, 2, 12, 0, 30, 0, '+01:00') },
      expected: %w(scalars) },

    # The same instant answers the same rows however it travels — as a Ruby
    # moment, its as_json string or its to_s string.
    { desc: "a zoned moment matches the date in the site's timezone",
      conditions: { held_on: TRANSPORT_MOMENT },
      expected: %w(scalars) },

    { desc: "an as_json moment matches the date in the site's timezone",
      conditions: { held_on: TRANSPORT_MOMENT.as_json },
      expected: %w(scalars) },

    { desc: "a to_s moment matches the date in the site's timezone",
      conditions: { held_on: TRANSPORT_MOMENT.to_s },
      expected: %w(scalars) },

    { desc: 'a to_s moment bounds a date_time field',
      conditions: { 'at.lte' => '2012-06-06 15:00:00 +0300' },
      expected: %w(scalars) },

    { desc: 'eq text in another encoding',
      conditions: { name: 'Scalars'.encode(Encoding::UTF_16LE) }, expected: %w(scalars) },

    { desc: 'eq text in no readable encoding matches nothing',
      conditions: { name: %(caf\xFF) }, expected: [] },

    { desc: 'an unreadable list element cannot match, the readable ones still do',
      conditions: { 'name.in' => ['Scalars', %(caf\xFF)] }, expected: %w(scalars) },

    { desc: 'eq text in no readable encoding on an integer field matches nothing',
      conditions: { score: %(5\xFF) }, expected: [] },

    { desc: 'gt text in no readable encoding on an integer field matches nothing',
      conditions: { 'score.gt' => %(1\xFF) }, expected: [] },

    { desc: 'an embedded document with an unreadable key matches nothing',
      conditions: { payload: { %(caf\xFF) => 1 } }, expected: [] },

    { desc: 'a range with a bound in no readable encoding matches nothing',
      conditions: { name: 'a'..%(caf\xFF) }, expected: [] }
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

    { desc: 'a raw Mongo operator spelled in another encoding',
      conditions: { 'payload' => { '$gt'.encode(Encoding::UTF_16BE) => 1 } },
      error: Locomotive::Steam::Adapters::Query::UnsupportedOperator },

    { desc: 'a raw Mongo operator inside an array value',
      conditions: { 'name' => [{ '$ne' => 'Scalars' }] },
      error: Locomotive::Steam::Adapters::Query::UnsupportedOperator },

    { desc: 'a structural comparison operand',
      conditions: { 'score.gt' => [1] },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'a boolean operand for a numeric field',
      conditions: { 'score.gt' => true },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    # Typed integers outside BSON int64 and non-finite floats are invalid operands.
    { desc: 'an integer beyond int64',
      conditions: { 'score.gt' => 2**63 },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'a float that is not finite',
      conditions: { 'price.gt' => Float::INFINITY },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'an array size past int32',
      conditions: { 'labels.size' => 2**31 },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'a Rational operand',
      conditions: { 'score.gt' => Rational(3, 2) },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'a BigDecimal operand',
      conditions: { 'price.gt' => BigDecimal('1.5') },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'a Rational bound inside a Range',
      conditions: { score: (Rational(1, 2)..Rational(3, 2)) },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'an ordering on the primary key',
      conditions: { '_id.gt' => 'a' },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'a Range on the primary key',
      conditions: { _id: ('a'..'z') },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'a Regexp on the primary key',
      conditions: { _id: /scal/ },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'an ordering on a select field',
      conditions: { 'category.gt' => 'alpha' },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'a Regexp on a select field',
      conditions: { category: /alph/ },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'an ordering on a belongs_to field',
      conditions: { 'maker.gt' => 'maker-one' },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'a Regexp on a many_to_many field',
      conditions: { topics: /topic/ },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'a Regexp inside a select list',
      conditions: { 'category.in' => [/alph/] },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'a Regexp inside a belongs_to document',
      conditions: { maker: { _id: /maker/ } },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'one field named twice under different spellings',
      conditions: { :name => 'Scalars', 'name' => 'Zero' },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'a key named twice inside a value',
      conditions: { payload: { :a => 1, 'a' => 2 } },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'an order_by on the primary key',
      conditions: { order_by: '_id' },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'an order_by on a select field',
      conditions: { order_by: 'tier' },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'an order_by on an association',
      conditions: { order_by: 'topics' },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'an order_by on an array field',
      conditions: { order_by: 'labels' },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'an order_by on a json field',
      conditions: { order_by: 'payload' },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'an order_by on a field the type does not declare',
      conditions: { order_by: 'nonexistent' },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'an order_by on a position no association of this type keeps',
      conditions: { order_by: 'position_in_nothing' },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'an order_by criterion naming more than a field and a direction',
      conditions: { order_by: 'name asc desc' },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'an exists operand in no readable encoding',
      conditions: { 'title.exists' => %(tru\xFF) },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'an order_by criterion in no readable encoding',
      conditions: { order_by: %(name\xFF asc) },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'a field name in no readable encoding',
      conditions: { %(caf\xFF) => 'x' },
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

  end

  context 'MongoDB' do

    before(:all) { AdapterParityFixture.seed_mongodb! }
    after(:all)  { AdapterParityFixture.cleanup! }

    it_should_behave_like 'the query semantics' do
      let(:adapter) { AdapterParityFixture.mongodb_adapter }
    end

  end

  context 'Filesystem' do

    it_should_behave_like 'the query semantics' do
      let(:adapter) { AdapterParityFixture.filesystem_adapter }
    end

  end

end
