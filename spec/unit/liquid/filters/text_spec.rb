require 'spec_helper'

describe Locomotive::Steam::Liquid::Filters::Text do

  include Locomotive::Steam::Liquid::Filters::Text

  let(:services)  { Locomotive::Steam::Services.build_instance }
  let(:context)   { instance_double('Context', registers: { services: services }) }

  before { @context = context }

  it 'transforms a textile input into HTML' do
    expect(textile('This is *my* text.')).to eq "<p>This is <strong>my</strong> text.</p>"
  end

  it 'transforms a markdown input into HTML' do
    expect(markdown('# My title')).to eq "<h1>My title</h1>\n"
  end

  it 'underscores an input' do
    expect(underscore('foo')).to eq 'foo'
    expect(underscore('home page')).to eq 'home_page'
    expect(underscore('My foo Bar')).to eq 'my_foo_bar'
    expect(underscore('foo/bar')).to eq 'foo_bar'
    expect(underscore('foo/bar/index')).to eq 'foo_bar_index'
  end

  it 'dasherizes an input' do
    expect(dasherize('foo')).to eq 'foo'
    expect(dasherize('foo_bar')).to eq 'foo-bar'
    expect(dasherize('foo/bar')).to eq 'foo-bar'
    expect(dasherize('foo/bar/index')).to eq 'foo-bar-index'
  end

  it 'concats strings' do
    expect(concat('foo', 'bar')).to eq 'foobar'
    expect(concat('hello', 'foo', 'bar')).to eq 'hellofoobar'
  end

  it 'concats arrays like the Liquid built-in filter' do
    expect(concat([1, 2], [3, 4])).to eq [1, 2, 3, 4]
    expect(concat([1, [2]], [3])).to eq [1, 2, 3]
    expect { concat([1, 2], 'x') }.to raise_error(::Liquid::ArgumentError)
  end

  describe 'concat rendered through Liquid' do

    subject { render_template("{{ 'hello' | concat: 'foo', 'bar' }}", ::Liquid::Context.new) }

    it { is_expected.to eq 'hellofoobar' }

    context 'with arrays' do

      subject { render_template("{{ list | concat: more | join: '-' }}", ::Liquid::Context.new({ 'list' => [1, 2], 'more' => [3] }, {}, {})) }

      it { is_expected.to eq '1-2-3' }

    end

    context 'inside a loop' do

      # the template literal must not accumulate the previous iterations
      subject { render_template("{% for x in list %}{{ 'i' | concat: '-', x }} {% endfor %}", ::Liquid::Context.new({ 'list' => %w(a b c) }, {}, {})) }

      it { is_expected.to eq 'i-a i-b i-c ' }

    end

  end

  it 'encodes an input' do
    expect(encode('http:://www.example.com?key=hello world')).to eq 'http%3A%3A%2F%2Fwww.example.com%3Fkey%3Dhello+world'
  end

  it 'parameterizes an input' do
    expect(parameterize('séjourner & dormir')).to eq 'sejourner-dormir'
  end

  it 'replaces \n by <br/>' do
    expect(multi_line("hello\nworld")).to eq 'hello<br/>world'
  end

  it 'right justifies and padds a string' do
    expect(rjust('42', 4, '.')).to eq '..42'
  end

  it 'left justifies and padds a string' do
    expect(ljust('42', 4, '.')).to eq '42..'
  end

end
