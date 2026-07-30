require 'spec_helper'

describe Locomotive::Steam::Liquid::Tags::Concerns::AttributesParser do

  let(:host_class) do
    Class.new do
      include Locomotive::Steam::Liquid::Tags::Concerns::AttributesParser
    end
  end

  let(:parser) { host_class.new }

  def parse(markup)
    parser.parse_markup(markup)
  end

  describe 'the accepted DSL (behaviour preserved across the parser backend)' do

    it 'parses a symbol-keyed integer' do
      expect(parse('a: 1')).to eq(a: 1)
    end

    it 'parses booleans, integers, floats and strings' do
      expect(parse("active: true, price: 42, ratio: 3.14, title: 'foo', hidden: false"))
        .to eq(active: true, price: 42, ratio: 3.14, title: 'foo', hidden: false)
    end

    it 'parses nested arrays' do
      expect(parse('tags: [1, 2, [3, 4]]')).to eq(tags: [1, 2, [3, 4]])
    end

    it 'parses a nested hash' do
      expect(parse('nested: { a: 1 }')).to eq(nested: { a: 1 })
    end

    it 'parses a regexp with flags' do
      expect(parse('title: /foo/imx')).to eq(title: /foo/mix)
    end

    it 'keeps the last value on a repeated key' do
      expect(parse('a: 1, a: 2')).to eq(a: 2)
    end

    it 'turns an operator suffix into a dotted symbol key' do
      expect(parse('f.gt: 5')).to eq(:'f.gt' => 5)
    end

    it 'parses a bare identifier into a Liquid variable lookup' do
      value = parse('ref: bare')[:ref]
      expect(value).to be_a(::Liquid::VariableLookup)
      expect(value.name).to eq 'bare'
      expect(value.lookups).to eq []
    end

    it 'parses a dotted identifier into a Liquid variable lookup' do
      value = parse('ref: some.thing')[:ref]
      expect(value).to be_a(::Liquid::VariableLookup)
      expect(value.name).to eq 'some'
      expect(value.lookups).to eq ['thing']
    end

    it 'decodes a + operation to its left operand (no arithmetic)' do
      expect(parse('price: 41 + 1')).to eq(price: 41)

      value = parse('price: some.thing + 1')[:price]
      expect(value).to be_a(::Liquid::VariableLookup)
      expect(value.name).to eq 'some'
    end

  end

  describe 'the documented many-to-many all syntax' do

    it 'normalizes the legacy string form into a list' do
      expect(parse(%q{categories.all: "$and: ['A', 'B']"})).to eq(:'categories.all' => %w(A B))
    end

    it 'accepts integer ids and an empty list' do
      expect(parse(%q{categories.all: "$and: [1, 2]"})).to eq(:'categories.all' => [1, 2])
      expect(parse(%q{categories.all: "$and: []"})).to eq(:'categories.all' => [])
    end

    it 'leaves any other string as an ordinary one-element operand' do
      expect(parse(%q{tags.all: 'featured'})).to eq(:'tags.all' => 'featured')
      expect(parse(%q{tags.all: '$andsomething'})).to eq(:'tags.all' => '$andsomething')
    end

    it 'only applies to the all operator' do
      expect(parse(%q{tags.in: "$and: ['A']"})).to eq(:'tags.in' => "$and: ['A']")
      expect(parse(%q{name: "$and: ['A']"})).to eq(name: "$and: ['A']")
    end

    it 'rejects a malformed or unsupported legacy form' do
      [
        %q{categories.all: "$and: ['A'"},
        %q{categories.all: "$and: {a: 1}"},
        %q{categories.all: "$and: [true]"},
        %q{categories.all: "$and: [1.5]"},
        %q{categories.all: "$and: ['A'], $or: ['B']"}
      ].each do |markup|
        expect { parse(markup) }.to raise_error(::Liquid::SyntaxError)
      end
    end

    it 'rejects what a YAML load would quietly accept' do
      {
        'a repeated key'      => %Q{$and: ['A']\n$and: ['B']},
        'a second document'   => %Q{$and: ['A']\n---\n$and: ['B']},
        'an alias'            => %q{$and: [*x]},
        'a tagged sequence'   => %q{$and: !ruby/object:Foo []}
      }.each do |desc, source|
        expect { parse(%{categories.all: #{source.dump}}) }
          .to raise_error(::Liquid::SyntaxError), "expected #{desc} to be rejected"
      end
    end

  end

  describe 'fail-closed: unparseable or unsupported markup raises Liquid::SyntaxError' do

    it 'raises on invalid syntax' do
      expect { parse('bad ][ syntax') }.to raise_error(::Liquid::SyntaxError)
    end

    it 'raises on an unsupported node (a method call on a constant)' do
      expect { parse('obj: Kernel.exit') }.to raise_error(::Liquid::SyntaxError)
    end

    it 'raises when the markup smuggles more than one statement' do
      expect { parse('a: 1}; Kernel.exit; {b: 2') }.to raise_error(::Liquid::SyntaxError)
    end

    it 'raises on a method call carrying arguments' do
      expect { parse('a: obj.meth(1)') }.to raise_error(::Liquid::SyntaxError)
    end

    it 'raises on a safe-navigation lookup' do
      expect { parse('ref: foo&.bar') }.to raise_error(::Liquid::SyntaxError)
    end

    it 'raises on a regexp once (o) flag' do
      expect { parse('title: /foo/o') }.to raise_error(::Liquid::SyntaxError)
    end

    it 'raises on a regexp encoding (u) flag' do
      expect { parse('title: /foo/u') }.to raise_error(::Liquid::SyntaxError)
    end

    it 'raises on an invalid regexp pattern instead of leaking a RegexpError' do
      expect { parse('title: /[z-a]/') }.to raise_error(::Liquid::SyntaxError)
    end

    it 'validates the right operand of a + operation' do
      expect { parse('price: 1 + Kernel.exit') }.to raise_error(::Liquid::SyntaxError)
    end

  end

end
