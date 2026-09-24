# Steam query semantics

Steam exposes one query API over Wagon's filesystem data and Engine's MongoDB
data. This document defines queries over content entries: their shared
behaviour and the remaining storage-specific differences. Queries owned by
other repositories, including pages, are outside its scope.

Query criteria accept Steam operators only. Raw MongoDB operators are
rejected and never sent to the storage driver.

Use `with_scope` to filter a collection and `limit` to restrict the number
of entries rendered:

```liquid
{% with_scope price.gte: 100 %}
  {% for product in contents.products limit: 20 %}
    {{ product.title }}
  {% endfor %}
{% endwith_scope %}
```

## Query interfaces

Content entries can be queried from Liquid templates, the Ruby repository
API, and `{% action %}` JavaScript. They share criteria and matching
semantics; only Liquid template criteria are restricted to public field
names.

**Template criteria** are `{% with_scope %}` markup and a runtime hash
(`{% with_scope my_filters %}`), whose names are checked like markup names.
They name declared content type fields or the public system names `_id`,
`_slug`, `_visible`, `_position`, `created_at` and `updated_at`, plus a plain
`order_by` for the ordering stage. A top-level `_permalink` key is an alias
for `_slug`, so naming both in one hash is a duplicate key; with an operator
or inside an embedded document it is not. Any other name (persisted,
internal, SEO or unknown) raises `Query::InvalidValue` when a collection
receiving the criteria is queried (below).

**The Ruby repository API**, direct calls such as `repository.all(criteria)`,
does not restrict criteria to template-visible names: it accepts persisted
names as direct id criteria (see below), `Range` and `Regexp` objects and
direct ids. Subject to the schema collision and non-queryable-field guards,
internal, SEO and unknown names reach the store as written, where they match
only what is stored under them.

**`{% action %}` JavaScript**: `allEntries(type, criteria)` passes a plain
`Hash` to the repository, so criteria names follow the Ruby API rules.
`findEntry(type, value)` takes no criteria: it looks the value up as a slug,
then as an adapter id. Query failures are exposed as
`Locomotive::Steam::ActionError`.

On every interface a schema name may not have more than one owner: a schema
cannot declare a field over a name Steam stores, writes or serves, nor two
fields sharing a declared or derived name. Every name of a colliding group
is refused. `has_many` fields cannot be queried on the parent entry: the
relationship is stored on the children. Password fields and their hash and
confirmation attributes are also not queryable. This includes `exists` and
`size`.

### How `with_scope` selects a content type

The first query that uses the criteria selects the content type for the
current Liquid scope: enumerating, counting or taking `first` of a
`contents.<type>` collection or of a `has_many` or `many_to_many`
association. Reading a collection without querying it
(`{% assign topics = entry.topics %}`) selects nothing. Once a type is
selected, a `contents` collection of another type is queried without the
criteria, and an association receives them only when its target type is the
selected type or its field name is that type's slug. A `belongs_to` never
receives criteria: its target is fetched by its stored id. Criteria names
are validated against the schema of each collection that receives them.

The selection belongs to the Liquid scope where the selecting query runs,
not to the whole block. A `for` or `tablerow` collection is evaluated in the
enclosing scope, so its selection holds for the rest of the block; a first
query inside a loop body or an `include` is forgotten when that scope ends,
and a later collection in the block selects the type again. Write one block
per collection or association.

### Persisted names

A `belongs_to` or `select` field is persisted as `<name>_id`; a
`many_to_many` field as `<singularized_name>_ids`. Criteria using these
persisted names interpret their operands as **ids**, never as slugs or
option names. `nil` keeps the missing/null semantics of the declared name; a
`Symbol` is converted to its text and used as an id; a lone id on a
list-valued name is a membership test. `in`/`nin`/`all` accept flat id
lists: a nested list element raises, and so does an `Array` under `eq` or
`ne`. An `{_id: ...}` hash is not unwrapped here: it is an embedded document,
which no stored id equals.

A stored id is adapter-specific (see *Where the two stores differ*), so a
literal id in a template or fixture is not portable. Portable association
criteria use the declared name with a slug or an entry; select criteria use
an option name. An `{_id: ...}` document must carry an id the current
adapter can convert.

## Operators

A query key is a field name with an optional `.operator` suffix
(`price.gte`). Empty names and keys with multiple dots raise. The dot is
reserved for operators: `maker.name` names an unknown operator, not a nested
path.

| operator | suffix in `with_scope` | matches |
|----------|------------------------|---------|
| `eq`     | no  | the whole stored value, or one element of an array field |
| `ne`     | yes | the negation of `eq` |
| `in`     | yes | one of the listed values; `in []` matches nothing |
| `nin`    | yes | the negation of `in`, so `nin []` matches everything |
| `all`    | yes | every listed value the way `eq` matches it; repeats and order do not matter; an empty list matches nothing |
| `gt`     | yes | greater than; an array field matches when one element does; missing and null never match |
| `gte`    | yes | greater than or equal |
| `lt`     | yes | less than |
| `lte`    | yes | less than or equal |
| `exists` | yes | key presence in the query's locale: `true` matches a null value too, `false` only a missing key |
| `size`   | yes | an **array** field with exactly N elements |

- **Equality** carries no suffix (`field: value`). The Ruby API also spells
  it `.eq` or `.==`, which alias each other but not the bare key: only a
  bare key accepts a `Regexp` or a `Range`, and `name` with `name.eq` is two
  criteria, while `name.eq` with `name.==` names one criterion twice and
  raises.
- **List operators** (`in`, `nin`, `all`) take an `Array`
  (`{% with_scope categories.all: ['A', 'B'] %}`), or a lone value as the
  list of one.
- **`exists`** takes `true`, `false`, or those two words in any case; `"1"`
  and `"0"` raise.
- **`size`** takes an `Integer`, or a `String` of one to ten decimal digits,
  between 0 and `2**31 - 1`; anything else raises, `2.0` included.

### Regexp and Range

Neither has a markup form: a regexp literal (`title: /foo/i`) or a range
literal (`price: 1..3`) is a `Liquid::SyntaxError`. Every quoted value is
text whatever it looks like (`'/about/'` and `'/foo/i'` are strings), and a
runtime `String` stays text: what a visitor typed never becomes a pattern.
Both reach a query only as Ruby **objects**, through the Ruby API or a
runtime hash. A `Regexp` or `Range` must be the entire value of an
unsuffixed criterion: under `.eq`/`.ne`, in a list operator, or nested
inside an `Array` or a `Hash`, on any field, it raises.

A `Regexp` matches string values only, array elements included. It must be
encoded as UTF-8, or as US-ASCII without a fixed encoding, and hold no NUL
byte; any other `Regexp` raises. Each store runs the pattern in its own
regular-expression engine and their dialects are not reconciled, so a
portable pattern uses syntax both engines accept. There is no `contains`
operator.

A `Range` becomes its bounds: `1..3` inclusive, `1...3` exclusive at the
end, `1..` and `..3` one-sided. A range with neither bound is rejected. Each
bound follows the corresponding scalar comparison rules. Numeric and date
fields parse text bounds through their field grammar, and text they cannot
parse makes the range match nothing. A moment bound on a `date` field names
the site's day. A bound of a Ruby type the field cannot convert, a
structural bound included, raises. Fields without field-specific coercion
use the shared comparison rules, and a `boolean` field takes no range at
all, whatever its bounds. On an array field a `Range` does not mean
"contains an element inside the range": each bound is tested independently,
so different elements may satisfy the lower and the upper comparison.

## Values

- Criteria are a `Hash`, or `nil` for none; embedded documents are `Hash`es
  and explicit lists are `Array`s. Other `Enumerable` values are rejected; a
  `Range` is never enumerated.
- A numeric operand must be an `Integer` within int64 or a finite `Float`.
  This applies to every field, list element, embedded document value and
  range bound. Any other `Numeric`, `BigDecimal` and `Rational` included,
  raises.
- A `Hash` operand is an embedded document: `$`-prefixed keys are rejected,
  keys are normalized to `String` (two that collide raise), and **key order
  matters**, as it does in MongoDB.
- A `Symbol` stands for the string it spells, in an operand and in a stored
  value. Where a field's own grammar parses the operand (`boolean`, numeric
  and date fields, `exists` and `size`), a `Symbol` raises.
- Equality with `nil` means null-or-missing. Comparing against `nil`
  (`gt`/`gte`/`lt`/`lte`) matches nothing.
- A comparison takes one `Comparable` value: a structural operand
  (`score.gt: [1]`) raises. `false` orders before `true`, so
  `flag.gt: false` matches `true`.

## Field-aware rules

Once the content type is known, an operand is normalized for its field type:
each criterion on its own, element by element in a list, `exists` and `size`
operands left alone.

An operand may fail to identify any stored value: text a field's grammar
cannot parse, an unresolved slug or option name, or an explicit id the
current adapter cannot convert. Such an operand matches nothing under
equality, adds no restriction under `ne`, is discarded from `in` and `nin`,
and makes `all` match nothing. Under a comparison, unparseable text still
matches nothing, while an unresolved slug, option name or id raises: those
live on fields matched by id, which have no order.

A wrong Ruby type raises on a field with its own value grammar: numeric,
`boolean`, `date` and `date_time`. A field matched by id resolves any other
operand as an option name or passes it to the store as an id, and one that
resolves to neither matches nothing.

- **numeric fields** parse a `String` in base ten and no other notation,
  capped at 64 bytes: an `integer` field takes digits and a sign, a `float`
  field also a decimal point and an exponent. For integer text, leading
  zeros are removed before checking the 19-digit limit; the sign is
  preserved. Text past the cap, and underscored, hexadecimal, overflowing or
  blank text, cannot be parsed. Surrounding whitespace is trimmed from
  numeric and date text; for numeric text it still counts toward the 64-byte
  cap, measured before trimming and transcoding.
- **date and date_time fields** accept these operands:

  | operand | `date` | `date_time` |
  |---|---|---|
  | `YYYY-MM-DD` or a `Date` | that day | site midnight |
  | `YYYY/MM/DD` | that day | cannot be parsed |
  | a moment (below) or a Ruby time-like value | the site's calendar day of the moment | the moment |

  A moment is `YYYY-MM-DDTHH:MM[:SS[.fraction]]` with an optional `Z`,
  `±HHMM` or `±HH:MM` offset, or Ruby `Time#to_s`
  (`YYYY-MM-DD HH:MM:SS +ZZZZ` or `... UTC`). An offset past `±23:59`
  cannot be parsed. An impossible calendar day (`2019-02-29`) is refused on
  every form and both field types, while a real leap day parses.

  Parsing text or a `Date` as `date_time` needs the site's timezone: it
  supplies the zone when the operand has no offset, while an explicit offset
  still determines the instant. Resolving a moment to a `date` field's day
  needs the timezone too. A Ruby time-like value used as `date_time` keeps
  its instant without consulting it. A site that declares no timezone uses
  UTC. A missing site, or a timezone name that resolves to no zone, raises
  `ContentFieldValues::ConfigurationError`, not a query error; on Filesystem
  it raises while the type's entries load, once one of them needs the zone,
  so no query of that type runs while other types load normally.
- **boolean fields** accept `true`, `false` and the strings a form sends
  (`"true"`, `"false"`, `"1"`, `"0"`), whitespace-trimmed and
  case-insensitive.
- **select fields** are queried by option name, resolved to the stored id.
  Option names are resolved in the query's locale on a localized select and
  in the site's default locale otherwise.
- **associations** treat a `String` or `Symbol` as a target slug, a
  24-character hex string included. A hidden target counts as unresolved,
  so reaching one takes its id or the persisted name. An explicit id is an
  entry, an adapter id object, or an `{_id: ...}` hash. An `{_id: nil}` or
  `_id`-less hash, and an entry whose id the adapter cannot convert, are
  unmatchable; only a bare `nil` keeps its missing-or-null meaning. On a
  `many_to_many` a lone operand tests one link:

  | `many_to_many` criterion | means |
  |---|---|
  | `topics: 'news'` | linked to the topic with slug `news` |
  | `topics: entry` / `{_id: id}` | linked to the topic with that id |
  | `topics.ne: 'news'` | not linked to that topic |
  | `topics.size: 0` | the stored id list exists and is empty |
  | `topics: nil` | no stored list, a null list, or a list holding null |
  | `topics: [...]`, `topics.ne: [...]` | raises: outside a list operator the field takes one value, an empty list included |

  In a list operator an `{_id: ...}` hash is one element. A composite
  identity (an `_id` given as a list of ids naming one entry, such as
  `[store_id, slug]`) matches through any of them; `ne` and `nin` require
  all of them absent and `all` rejects it. An exact-set query is not
  offered: `all` with `size` is equivalent only when neither the query nor
  the stored list contains duplicates.

A field matched by id (`_id`, a `select`, a `belongs_to` or a
`many_to_many`) takes neither a `Regexp` nor a `Range`, and no ordering
comparison (`gt`/`gte`/`lt`/`lte`): all of them raise. Its list operators
take a flat list, and a nested list element raises.

## Missing vs nil

| query | missing field | present, `nil` | present, non-null scalar |
|-------|---------------|----------------|--------------------------|
| `eq nil`   | match   | match     | no    |
| `ne nil`   | no      | no        | match |
| `in [nil]` | match   | match     | no    |
| `nin [nil]` | no      | no        | match |
| `all [nil]` | match   | match     | no    |
| `exists true`  | no  | match     | match |
| `exists false` | match | no      | no    |

`eq nil`, `in [nil]` and `all [nil]` also match an array containing `nil`;
`ne nil` and `nin [nil]` exclude it. `exists` still sees a present field.
On a localized field these states apply per locale: a translation the
query's locale does not carry counts as a missing field, while one
explicitly set to null counts as present and null.

## What raises

For the direct query API, *raises* means `Query::InvalidValue` unless
another class is named. An unknown or raw Mongo operator raises
`Query::UnsupportedOperator`: a `$`-prefixed key is rejected at any
supported `Hash`/`Array` depth (`$where`, `note: { $gt: 5 }`), while a
`'$100'` **value** is ordinary data. An error `with_scope` detects while
parsing or evaluating its criteria, a runtime hash's structure included, is
reported as `Liquid::SyntaxError`; schema and field-aware operand errors are
detected when the query runs and raise `Query::InvalidValue`.

Query text is transcoded to UTF-8 before interpretation. Unreadable operands
follow the field-aware failure rules, including inside embedded documents
and range bounds. Unreadable top-level criterion names, operators and
ordering criteria raise, as does an operand for `exists` or `size`, whose
grammars accept no unreadable text.

## Composition and windows

### Combining criteria

Several `where` calls are combined with **and**, including calls for the
same field. A Hash of criteria may hold both `price.gte` and `price.lte`,
but may not repeat a normalized key, and may not carry a declared name
together with its persisted name under the same operator: `maker` with
`maker_id` raises, while `maker` with `maker_id.eq` is two criteria. Inside
an embedded document a colliding key always raises.

Repository scopes compose the same way: the content type bound, an
association's bound and the caller's criteria are separate clauses combined
with **and**. A caller cannot overwrite them, so contradicting a scope
matches nothing. Only `order_by` is not a filter and has precedence: the
caller's ordering wins over the scope's default. An explicit `order_by: nil`
is no ordering at all and defers to that default; unlike `_visible: nil`
below, it disables nothing.

### Visibility

With no explicit `_visible`, every content-entry query made through the
criteria API carries the default visibility clause `_visible: true`. An
explicit `_visible` suppresses only that default: `true` or `false` adds its
own clause (`false` returns the hidden entries), while `nil` adds none,
leaving visible, hidden and entries without the field alike. On this one key
`nil` disables the default filter instead of meaning null-or-missing, a
deliberate exception. Any other value raises, and so does any operator
suffix. `_visible` controls publishing, not authorization: hidden entries
must not hold secrets.

### The raw query block

The raw `repository.query { }` block is a trusted internal adapter
interface: it uses persisted names and bypasses schema validation, the
content type clause and default visibility, while the adapter's site
boundary still applies. On MongoDB the block therefore queries the site's
whole entry collection; a Filesystem repository queries only its content
type's entries, hidden ones included.

### Windows

Inside a criteria Hash only `order_by` is reserved. `limit` and `offset`
are not window options there: template criteria may use them only as
declared field names; Ruby criteria treat them as ordinary fields. A window
comes from the `offset` and `limit` methods: `offset` applies before
`limit`, and both take `nil` or an integer between 0 and `2**63 - 1`;
anything else raises. `limit(0)` returns no rows on either store, with
criteria checked even then. Unlike `where`, they do not accumulate: a second
call replaces the first, so a later `limit` can widen or lift an earlier
one, `limit(0)` included. A template `for` or `tablerow` window clamps its
computed start and end indexes to the supported range instead of raising.
Non-numeric input differs: `for` raises `Liquid::ArgumentError`, while
`tablerow` converts it to `0`, so `limit: 'abc'` iterates no entries (the
tag may still render an empty row) and `offset: 'abc'` starts at the first
entry. Bound large collections with `paginate` or such a window: an
unmaterialized MongoDB collection maps only the window's documents, while
Filesystem already holds the site dataset in memory.

## Ordering

`order_by` accepts `name`, `name.asc`, `name desc`, `name|desc`, a
comma-separated list, a `Hash` (`{ name: :desc }`, `{ _position: 1 }`, `-1`
descending), a flat array of fields (`['name', 'created_at desc']`), or
nested `[field, direction]` pairs (`[[:name, :desc]]`). A flat array lists
fields only, so `[:name, :desc]` names two fields. A missing direction is
`asc`.

Content entries may be ordered only by fields that both stores order alike:
`string`, `text`, `integer`, `float`, `boolean`, `date`, `date_time`, the system
fields `_slug`, `_position`, `_visible`, `created_at` and `updated_at`, and an
entry's position within an association (`position_in_<belongs_to>`, named after
the entry's own `belongs_to` field). An unknown direction, a malformed spec, a
field repeated in one sort, or any other field raises. `_position` is then
appended as a tie-breaker, following the primary criterion's direction. No
tie-breaker is appended when the sequence already contains `_position` or the
current locale's `_slug`. A localized field is ordered by its value in the
query's locale.

Associations enumerate in a defined order. A `many_to_many` follows the
owner's stored id sequence; a `has_many` follows `position_in_<inverse>` and
breaks ties by `_position`. An `order_by` declared on the association field
overrides that default, and a caller's runtime `order_by` wins over both.

`nil` sorts below the values that can be ordered: first ascending, last
descending. A field an entry does not carry sorts as `nil`. `Integer` and
`Float` compare with each other, as do `String` and `Symbol`. Otherwise a
field mixing types is unsupported: MongoDB orders across BSON types, while
Filesystem converts a declared field's stored value through its type (a
value of the wrong type sorts as `nil`) and raises `ArgumentError` for other
values it cannot compare.

## Where the two stores differ

- **IDs.** A Filesystem entry normally takes its slug as its id, and a
  Filesystem select option its position in the declaration (an `Integer`,
  or a `String` when the options are declared per locale), while MongoDB
  issues an `ObjectId` for both, so the same `_id` need not name the same
  logical entry. Portable entry lookups use `_slug` or `by_slug`.
- **Projections** (`only`). MongoDB applies one, Filesystem ignores it.
- **Localized fields stored as scalars.** Filesystem returns such a value
  in every locale: every value operator and ordering see it, while `exists`
  counts it absent. MongoDB has no `<name>.<locale>` path for it and treats
  it as a missing field. A Filesystem slug generated, or given as one value,
  is not such a value: it is held in every site locale when the entries
  load or an entry is created, while a slug given per locale keeps exactly
  the locales it names.
- **Time precision.** MongoDB truncates a stored `date_time` to
  milliseconds, while Filesystem keeps a Ruby `Time`'s full precision. Steam
  writes `created_at` and `updated_at` at millisecond precision on both.
