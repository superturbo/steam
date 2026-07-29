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
