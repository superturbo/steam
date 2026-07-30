# Canonical query semantics, verified identically against every storage adapter
# — MongoDB (Engine) and Filesystem->Memory (Wagon) — so the two products render
# a site the same way. Each case pins the exact rows by their stable, unique
# _slug (place/name repeat across years, so a wrong-row match must not pass).
# The contract is documented in docs/query_semantics.md; the table grows as later
# phases align the engines, so every commit stays green.
#
# Fixture caveat: the MongoDB seed applied type defaults the Filesystem YAML
# omits, so a few fields drift between the stores (price is 0.0 in Mongo vs
# missing in YAML; one city defaulted to "Chicago"). Cases here use fields and
# thresholds immune to that drift; do not add a price.lt or a missing-city case
# without reseeding the dump.
module QueryParity

  # every event without a tags field (all but the two 2012 tagged rows)
  UNTAGGED_EVENTS = %w(
    avogadros-number avogadros-number-1 ballydoyles ballydoyles-1
    brownes-market-1 kellys-westport-inn-1 quixotes-true-blue
    quixotes-true-blue-1 the-belmont the-belmont-1
  ).freeze

  CASES = [
    { desc: 'scalar equality on a select field',
      type: 'bands', conditions: { kind: 'grunge' },
      expected: %w(alice-in-chains pearl-jam) },

    { desc: 'equality on a boolean field',
      type: 'bands', conditions: { featured: true },
      expected: %w(the-who) },

    { desc: 'ne on a scalar field',
      type: 'bands', conditions: { 'name.ne' => 'The who' },
      expected: %w(alice-in-chains pearl-jam) },

    { desc: 'order_by a single field ascending',
      type: 'bands', conditions: { order_by: 'name' },
      expected: %w(alice-in-chains pearl-jam the-who), ordered: true },

    { desc: 'order_by descending via a dotted direction',
      type: 'bands', conditions: { order_by: 'name.desc' },
      expected: %w(the-who pearl-jam alice-in-chains), ordered: true },

    { desc: 'order_by a Hash direction (-1)',
      type: 'bands', conditions: { order_by: { name: -1 } },
      expected: %w(the-who pearl-jam alice-in-chains), ordered: true },

    { desc: 'scalar equality on a string field',
      type: 'events', conditions: { state: 'Colorado' },
      expected: %w(avogadros-number avogadros-number-1
                   quixotes-true-blue quixotes-true-blue-1) },

    { desc: 'scalar equality selecting several rows',
      type: 'events', conditions: { city: 'Kansas City' },
      expected: %w(brownes-market brownes-market-1
                   kellys-westport-inn kellys-westport-inn-1) },

    { desc: 'a Regexp on a plain field',
      type: 'events', conditions: { city: /Kansas/ },
      expected: %w(brownes-market brownes-market-1
                   kellys-westport-inn kellys-westport-inn-1) },

    { desc: 'in on a scalar field',
      type: 'events', conditions: { 'place.in' => ['The Belmont', "Ballydoyle's"] },
      expected: %w(ballydoyles ballydoyles-1 the-belmont the-belmont-1) },

    { desc: 'in matching an array field element',
      type: 'events', conditions: { 'tags.in' => ['awesome'] },
      expected: %w(brownes-market kellys-westport-inn) },

    { desc: 'all against an array field',
      type: 'events', conditions: { 'tags.all' => ['awesome', 'open bar'] },
      expected: %w(brownes-market kellys-westport-inn) },

    { desc: 'gt on a numeric field',
      type: 'events', conditions: { 'price.gt' => 10 },
      expected: %w(brownes-market) },

    { desc: 'gte on a numeric field',
      type: 'events', conditions: { 'price.gte' => 5.5 },
      expected: %w(brownes-market kellys-westport-inn) },

    { desc: 'a scalar equals an array field element',
      type: 'events', conditions: { tags: 'awesome' },
      expected: %w(brownes-market kellys-westport-inn) },

    { desc: 'an array value matches a single-level array exactly',
      type: 'events', conditions: { tags: ['awesome', 'open bar'] },
      expected: %w(brownes-market kellys-westport-inn) },

    { desc: 'an array value must match exactly, not intersect',
      type: 'events', conditions: { tags: ['awesome'] }, expected: [] },

    { desc: 'an empty all matches nothing',
      type: 'events', conditions: { 'tags.all' => [] }, expected: [] },

    { desc: 'ne a non-null value also matches a missing field',
      type: 'events', conditions: { 'tags.ne' => 'awesome' },
      expected: UNTAGGED_EVENTS },

    { desc: 'eq nil matches a missing or null field',
      type: 'events', conditions: { tags: nil }, expected: UNTAGGED_EVENTS },

    { desc: 'ne nil matches only present, non-null fields',
      type: 'events', conditions: { 'tags.ne' => nil },
      expected: %w(brownes-market kellys-westport-inn) },

    { desc: 'nin — a missing field matches',
      type: 'events', conditions: { 'tags.nin' => ['awesome'] },
      expected: UNTAGGED_EVENTS },

    { desc: 'in [nil] matches a missing field',
      type: 'events', conditions: { 'tags.in' => [nil] },
      expected: UNTAGGED_EVENTS },

    { desc: 'exists true matches present fields',
      type: 'events', conditions: { 'tags.exists' => true },
      expected: %w(brownes-market kellys-westport-inn) },

    { desc: 'exists false matches absent fields',
      type: 'events', conditions: { 'tags.exists' => false },
      expected: UNTAGGED_EVENTS },

    { desc: 'size counts array elements',
      type: 'events', conditions: { 'tags.size' => 2 },
      expected: %w(brownes-market kellys-westport-inn) },

    { desc: 'a Range on a plain field matches its bounds',
      type: 'events', conditions: { price: (5..6) },
      expected: %w(kellys-westport-inn) },

    { desc: 'gt matches an element of an array field',
      type: 'events', conditions: { 'tags.gt' => 'o' },
      expected: %w(brownes-market kellys-westport-inn) },

    # 'open bar' meets the lower bound, 'awesome' the upper, neither both
    { desc: 'a Range lets different elements of an array field satisfy each bound',
      type: 'events', conditions: { tags: ('f'..'m') },
      expected: %w(brownes-market kellys-westport-inn) },

    { desc: 'a Regexp matches an element of an array field',
      type: 'events', conditions: { tags: /aweso/ },
      expected: %w(brownes-market kellys-westport-inn) },

    { desc: 'a Regexp against a non-string field matches nothing',
      type: 'events', conditions: { price: /5/ }, expected: [] },

    { desc: 'a Set value is normalized to an array',
      type: 'events', conditions: { tags: Set['awesome', 'open bar'] },
      expected: %w(brownes-market kellys-westport-inn) },

    { desc: 'a reordered array value matches nothing',
      type: 'events', conditions: { tags: ['open bar', 'awesome'] },
      expected: [] },

    { desc: 'all with a nested array operand matches the whole array field',
      type: 'events', conditions: { 'tags.all' => [['awesome', 'open bar']] },
      expected: %w(brownes-market kellys-westport-inn) },

    { desc: 'in with a nested array operand matches the whole array field',
      type: 'events', conditions: { 'tags.in' => [['awesome', 'open bar']] },
      expected: %w(brownes-market kellys-westport-inn) },

    # only two events carry a price (5.5 and 15.0), and the Mongo-only 0.0
    # default on the others matches neither condition, so both are drift-immune
    { desc: 'a numeric condition given as a String, the way params arrive',
      type: 'events', conditions: { 'price.gt' => '5' },
      expected: %w(brownes-market kellys-westport-inn) },

    { desc: 'a numeric list operand given as Strings',
      type: 'events', conditions: { 'price.in' => %w(5.5 6) },
      expected: %w(kellys-westport-inn) },

    { desc: 'a numeric condition a visitor filled with garbage matches nothing',
      type: 'events', conditions: { 'price.gt' => 'abc' }, expected: [] },

    { desc: 'gt against a nil operand matches nothing',
      type: 'events', conditions: { 'price.gt' => nil }, expected: [] },

    { desc: 'gte against a nil operand matches nothing',
      type: 'events', conditions: { 'price.gte' => nil }, expected: [] },

    { desc: 'lt against a nil operand matches nothing',
      type: 'events', conditions: { 'price.lt' => nil }, expected: [] },

    { desc: 'lte against a nil operand matches nothing',
      type: 'events', conditions: { 'price.lte' => nil }, expected: [] },
  ].freeze

  # Rejected inputs must fail the same way on every adapter, not just return
  # different rows. The table grows with each enforcement commit.
  ERROR_CASES = [
    { desc: 'a removed legacy operator (neq)',
      type: 'bands', conditions: { 'name.neq' => 'The who' },
      error: Locomotive::Steam::Adapters::Query::UnsupportedOperator },

    { desc: 'a removed legacy operator (matches)',
      type: 'bands', conditions: { 'name.matches' => 'who' },
      error: Locomotive::Steam::Adapters::Query::UnsupportedOperator },

    { desc: 'an unknown operator',
      type: 'bands', conditions: { 'name.bogus' => 'x' },
      error: Locomotive::Steam::Adapters::Query::UnsupportedOperator },

    { desc: 'a nested field path',
      type: 'bands', conditions: { 'address.location.ne' => 'x' },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'an empty field name',
      type: 'bands', conditions: { '' => 'x' },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'an empty field with an operator suffix',
      type: 'bands', conditions: { '.ne' => 'x' },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'a raw Mongo operator in a key',
      type: 'bands', conditions: { '$where' => 'sleep(1000)' },
      error: Locomotive::Steam::Adapters::Query::UnsupportedOperator },

    { desc: 'a raw Mongo operator nested in a value',
      type: 'bands', conditions: { 'name' => { '$ne' => 'The who' } },
      error: Locomotive::Steam::Adapters::Query::UnsupportedOperator },

    { desc: 'a raw Mongo operator inside an array value',
      type: 'bands', conditions: { 'name' => [{ '$ne' => 'The who' }] },
      error: Locomotive::Steam::Adapters::Query::UnsupportedOperator },

    { desc: 'a structural comparison operand',
      type: 'events', conditions: { 'price.gt' => [1] },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },

    { desc: 'a boolean comparison operand',
      type: 'events', conditions: { 'price.gt' => true },
      error: Locomotive::Steam::Adapters::Query::InvalidValue },
  ].freeze

end

shared_examples_for 'canonical query parity' do

  let(:site_locales)    { %w(en fr nb) }
  let(:site)            { Locomotive::Steam::Site.new(_id: site_id, locales: site_locales) }
  let(:locale)          { :en }
  let(:type_repository) { Locomotive::Steam::ContentTypeRepository.new(adapter, site, locale) }

  def parity_slugs(type_slug, conditions)
    repository = Locomotive::Steam::ContentEntryRepository.new(adapter, site, locale, type_repository)
    repository.with(type_repository.by_slug(type_slug)).all(conditions).map { |entry| entry._slug[locale] }
  end

  QueryParity::CASES.each do |c|
    it c[:desc] do
      slugs = parity_slugs(c[:type], c[:conditions])

      if c[:ordered]
        expect(slugs).to eq c[:expected]
      else
        expect(slugs).to match_array(c[:expected])
      end
    end
  end

  QueryParity::ERROR_CASES.each do |c|
    it "rejects #{c[:desc]}" do
      expect { parity_slugs(c[:type], c[:conditions]) }.to raise_error(c[:error])
    end
  end

end
