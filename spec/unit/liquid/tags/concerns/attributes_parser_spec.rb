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

    it 'parses nil and null alike' do
      expect(parse('_visible: nil')).to eq(_visible: nil)
      expect(parse('_visible: null')).to eq(_visible: nil)
      expect(parse(%q{tags.in: [nil, 'a']})).to eq(:'tags.in' => [nil, 'a'])
      expect(parse('nested: { k: nil }')).to eq(nested: { k: nil })
    end

    it 'parses nested arrays' do
      expect(parse('tags: [1, 2, [3, 4]]')).to eq(tags: [1, 2, [3, 4]])
    end

    it 'parses a nested hash' do
      expect(parse('nested: { a: 1 }')).to eq(nested: { a: 1 })
    end

    it 'refuses a key named twice, however it is spelled' do
      expect { parse('a: 1, a: 2') }.to raise_error(::Liquid::SyntaxError)
      expect { parse('a: 1, "a" => 2') }.to raise_error(::Liquid::SyntaxError)
      expect { parse('a: { b: 1, b: 2 }') }.to raise_error(::Liquid::SyntaxError)
    end

    it 'turns an operator suffix into a dotted symbol key' do
      expect(parse('f.gt: 5')).to eq(:'f.gt' => 5)
    end

    it 'takes a value that follows the colon immediately' do
      expect(parse('price.lt:50')).to eq(:'price.lt' => 50)
      expect(parse(%q{name.in:['a']})).to eq(:'name.in' => ['a'])
      expect(parse(%q{title.ne:'x'})).to eq(:'title.ne' => 'x')
      expect(parse(%q{title.ne:"x"})).to eq(:'title.ne' => 'x')
    end

    it 'takes an operator key after non-ascii text' do
      expect(parse(%q{title: 'Žalias', price.gte: 5}))
        .to eq(:title => 'Žalias', :'price.gte' => 5)
    end

    it 'takes a field name ruby spells otherwise' do
      expect(parse('case.in: [1]')).to eq(:'case.in' => [1])
      expect(parse('end.ne: 1')).to eq(:'end.ne' => 1)
      expect(parse('SKU.in: [1]')).to eq(:'SKU.in' => [1])
    end

    it 'allows whitespace between the operator suffix and the colon' do
      expect(parse('price.gte : 5')).to eq(:'price.gte' => 5)
      expect(parse("price.gte\n  : 5")).to eq(:'price.gte' => 5)
      expect(parse("price.gte\n\n: 5")).to eq(:'price.gte' => 5)
      expect(parse("price.gte\t: 5")).to eq(:'price.gte' => 5)
    end

    it 'refuses a field and an operator held apart by whitespace' do
      ['price . gte: 5', 'price .gte: 5', 'price. gte: 5'].each do |markup|
        expect { parse(markup) }.to raise_error(::Liquid::SyntaxError)
      end
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

  describe 'string operands' do

    it 'takes an all operand as the single value it reads as' do
      expect(parse(%q{tags.all: 'featured'})).to eq(:'tags.all' => 'featured')
    end

    it 'leaves strings unchanged for other operators' do
      expect(parse(%q{tags.in: "$and: ['A']"})).to eq(:'tags.in' => "$and: ['A']")
      expect(parse(%q{name: "$and: ['A']"})).to eq(name: "$and: ['A']")
    end

    it 'reads a quoted value as text whatever its shape' do
      expect(parse("url: '/about/'")).to eq(url: '/about/')
      expect(parse("path.in: ['/about/']")).to eq('path.in': ['/about/'])
      expect(parse("maker: { _id: '/about/' }")).to eq(maker: { _id: '/about/' })
      expect(parse("title: '/foo/i'")).to eq(title: '/foo/i')
    end

    it 'reads a path without a trailing slash as text' do
      expect(parse("url: '/about'")).to eq(url: '/about')
    end

    it 'reads a value shaped like an operator key as text' do
      expect(parse(%q{name: 'a.in: b'})).to eq(name: 'a.in: b')
      expect(parse(%q{name: "a.gt: b"})).to eq(name: 'a.gt: b')
      expect(parse(%q{name: "a\"b.in: c"})).to eq(name: 'a"b.in: c')
    end

    it 'reads it as text inside an array and a nested object' do
      expect(parse(%q{tags: ['x.in: y']})).to eq(tags: ['x.in: y'])
      expect(parse(%q{nested: { k: 'x.lt: y' }})).to eq(nested: { k: 'x.lt: y' })
    end

    it 'reads it as text in the middle of a sentence' do
      expect(parse(%q{title: 'see foo.ne: bar'})).to eq(title: 'see foo.ne: bar')
    end

    it 'takes an operator key alongside such a value' do
      expect(parse(%q{name.in: ['a.in: b']})).to eq(:'name.in' => ['a.in: b'])
      expect(parse(%q{a.gt: 1, title: 'x.in: y', b.lt: 2}))
        .to eq(:'a.gt' => 1, :title => 'x.in: y', :'b.lt' => 2)
    end

  end

  describe 'an all operand spelled as raw operator text' do

    it 'refuses it rather than reading it as a value nothing matches' do
      expect { parse(%q{categories.all: "$and: ['A', 'B']"}) }
        .to raise_error(::Liquid::SyntaxError, /Invalid value for categories\.all/)
    end

    it 'refuses it however it is spaced' do
      expect { parse(%q{categories.all: "  $and : ['A']"}) }.to raise_error(::Liquid::SyntaxError)
    end

    it 'refuses it under a string key too' do
      expect { parse(%q{"categories.all" => "$and: ['A']"}) }.to raise_error(::Liquid::SyntaxError)
    end

    it 'reads a string that only mentions the operator as text' do
      expect(parse(%q{categories.all: "text $and: value"})).to eq(:'categories.all' => 'text $and: value')
    end

    it 'reads it as an ordinary pair inside a nested object' do
      expect(parse(%q{payload: { "categories.all": "$and: ['A']" }}))
        .to eq(payload: { :'categories.all' => "$and: ['A']" })
    end

    it 'parses the array operand form' do
      expect(parse(%q{categories.all: ['A', 'B']})).to eq(:'categories.all' => %w(A B))
    end

    it 'leaves a value handed over at render time to the runtime' do
      value = parse('categories.all: some.var')[:'categories.all']
      expect(value).to be_a(::Liquid::VariableLookup)
      expect(value.name).to eq 'some'
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

    it 'refuses a regexp literal whatever its flags or pattern' do
      ['title: /foo/', 'title: /foo/imx', 'title: /foo/o', 'title: /foo/u',
       'title: /[z-a]/'].each do |markup|
        expect { parse(markup) }
          .to raise_error(::Liquid::SyntaxError, /regular expression literals are not supported in with_scope/)
      end
    end

    it 'raises on every range literal' do
      ['price: 1..3', 'price: 1...3', 'price: (1..3)', "price: 'a'..'c'",
       'price: 1..', 'price: ..3'].each do |markup|
        expect { parse(markup) }.to raise_error(::Liquid::SyntaxError)
      end
    end

    it 'validates the right operand of a + operation' do
      expect { parse('price: 1 + Kernel.exit') }.to raise_error(::Liquid::SyntaxError)
    end

  end

end
