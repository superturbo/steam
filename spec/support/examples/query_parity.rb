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

end
