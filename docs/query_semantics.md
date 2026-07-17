# Steam query semantics (canonical)

Steam is the rendering stack shared by **Wagon** and **Engine**. The host picks
the storage adapter:

- **Filesystem → Memory** (Wagon): reads a site from YAML, queries it in Ruby.
- **MongoDB** (Engine): a real database with tenant scoping.
- **Memory** also backs embedded sub-collections (`select_options`,
  `editable_elements`, `entries_custom_fields`) in **both** products.

Because both products must render the same site identically, a query must mean
the **same thing** on every adapter. This document is the canonical contract.
It describes the **target** behaviour; the engines are aligned to it across the
query-layer standardization, and each row is locked by
`spec/support/examples/query_parity.rb` (run against MongoDB *and*
Filesystem→Memory) as it lands.

Where a supported form has a MongoDB meaning, the canonical semantics follow
MongoDB. Heterogeneous comparisons (string vs integer) and BSON type ordering
are **outside the supported parity contract**.

## Operator registry

A query key is a field name with an optional `.operator` suffix (`price.gte`).
Values may be coerced per the operator's *value kind* before execution.

| operator | mongo    | value kind | public (`with_scope`) | meaning |
|----------|----------|------------|-----------------------|---------|
| `eq`     | `$eq`    | literal    | no | equal to a scalar, or the scalar is an element of an array field; an array value matches an equal single-level array |
| `ne`     | `$ne`    | literal    | yes | not equal — **including a missing field**; `ne nil` requires the field present and non-null |
| `in`     | `$in`    | list       | yes | the field (or one of its array elements) equals a value in the list; `in [nil]` matches missing + null; `in []` matches nothing |
| `nin`    | `$nin`   | list       | yes | none of the field's values appears in the list — **a missing field matches**; `nin []` matches everything |
| `all`    | `$all`   | list       | yes | an array field contains every listed value; a scalar field matches only a single-element list of that value; an **empty list matches nothing** |
| `gt`     | `$gt`    | scalar     | yes | greater than (missing/nil never matches) |
| `gte`    | `$gte`   | scalar     | yes | greater than or equal |
| `lt`     | `$lt`    | scalar     | yes | less than |
| `lte`    | `$lte`   | scalar     | yes | less than or equal |
| `exists` | `$exists`| boolean    | yes | key presence — `true` matches even a null value; `false` matches only documents **without** the field |
| `size`   | `$size`  | size       | yes | an **array** field with exactly N elements |

`==` is an alias of `eq`. There is no closed "unsupported" list: an operator
not in the registry raises `Query::UnsupportedOperator`.

### Plain field (no suffix)

A key without a suffix is a literal match, and is **not** the same as `.eq`:

- **scalar** → literal equality (also matches an array element, like Mongo).
- **`Regexp`** → a native regular expression match (Mongo `{f: /x/}`; it is
  **not** wrapped in `$eq`).
- **`Range`** → range bounds: `1..3` → `$gte: 1, $lte: 3`; `1...3` → `$gte: 1,
  $lt: 3` (the exclusive end is honoured). One-sided ranges keep the bound they
  have: `1..` → `$gte: 1`, `..3` → `$lte: 3`, `...3` → `$lt: 3`. A range with
  neither bound (`nil..nil`) raises `Query::InvalidValue`.

A `Regexp` and a `Range` are allowed **only** in a plain field (a `Range` as
bounds). Neither is accepted through an `.eq`/`.ne` suffix (those take scalars,
single-level arrays, or `nil` only) nor a list operator — a list over a `Range`
is **rejected**, never expanded, so a wide range cannot explode into a huge
`$in`.

## Value kinds

| kind      | accepts | coercions | rejects |
|-----------|---------|-----------|---------|
| `literal` | scalar, a single-level array of scalars, `nil` | — | `Regexp`, `Range`, `Set`, `Hash` |
| `scalar`  | a single comparable value | — | array, `Regexp`, `Range`, `Set`, `Hash` |
| `list`    | array, `Set`, or a lone scalar | `Set`→array; scalar→one-element array | `Range`, `Hash` (and Hash elements) |
| `boolean` | `true`, `false`, `"true"`, `"false"` (case-insensitive) | strings→boolean | anything else → `Query::InvalidValue` |
| `size`    | a non-negative integer, or its decimal string | `"2"`→`2` | negatives, fractions, non-numerics → `Query::InvalidValue` |

A plain `Hash` value is rejected: raw `$`-prefixed keys are caught first
(`Query::UnsupportedOperator`), any other Hash is `Query::InvalidValue`. A bare
`Set` outside a list operator is rejected (its match would depend on iteration
order). Nested arrays are rejected.

## Missing vs nil

The distinction is part of the contract. Each row is added to the parity
matrix alongside the implementation change that aligns both engines.

| query | missing field | present, `nil` | present, value |
|-------|---------------|----------------|----------------|
| `eq nil`   | match   | match     | no    |
| `ne nil`   | no      | no        | match |
| `in [nil]` | match   | match     | no    |
| `nin [nil]`| match   | no        | match |
| `ne <v>`   | match   | match     | no if equal |
| `exists true`  | no  | match     | match |
| `exists false` | match | no      | no    |

In Memory, field presence is read via `attributes.key?` (localized fields via
`translations.key?(locale)`, generic objects via `respond_to?`). A real
execution error is **not** swallowed as "missing".

## Fail-fast

The following raise rather than silently returning nothing:

- an unknown operator suffix (`price.approx`);
- a raw Mongo operator in a key **or** recursively in a value (`$where`,
  `price: { $gt: 5 }`) — enforced for **both** engines, so Wagon cannot accept
  an injection Engine rejects;
- a non-boolean `exists` value, a negative/fractional `size`;
- an unknown sort direction;
- a `Range`/`Regexp` where the value kind does not allow it;
- a plain `Hash` value.

## Ordering

`order_by` accepts `name`, `name.asc`, `name desc`, `name|desc`, a
comma-separated list, or a `Hash` (`{ position: 1 }`, `-1` for descending).
A missing direction defaults to `asc`; any other direction raises. It
normalizes to one neutral form — `[[:name, :asc], [:created_at, :desc]]` —
which both engines consume (MongoDB maps `:asc`/`:desc` to `1`/`-1`).

Null ordering is **not** unified (Memory sorts nil last, MongoDB null first);
it is out of parity scope.
