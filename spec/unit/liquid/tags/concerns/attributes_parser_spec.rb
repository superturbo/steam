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

    it 'refuses a key named twice, however it is spelled' do
      expect { parse('a: 1, a: 2') }.to raise_error(::Liquid::SyntaxError)
      expect { parse('a: 1, "a" => 2') }.to raise_error(::Liquid::SyntaxError)
      expect { parse('a: { b: 1, b: 2 }') }.to raise_error(::Liquid::SyntaxError)
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
