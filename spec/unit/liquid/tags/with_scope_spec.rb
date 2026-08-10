require 'spec_helper'

describe Locomotive::Steam::Liquid::Tags::WithScope do

  let(:assigns)     { {} }
  let(:context)     { ::Liquid::Context.new(assigns, {}, {}) }
  let(:output)      { render_template(source, context) }
  let(:conditions)  { context['conditions'] }

  describe 'no attributes' do

    let(:source)  { '{% with_scope %}42{% endwith_scope %}'}
    it { expect { output }.to raise_error("Liquid syntax error (line 1): Syntax Error in 'with_scope' - Valid syntax: with_scope <name_1>: <value_1>, ..., <name_n>: <value_n>") }

  end

  describe 'a removed or unknown operator is not recognised' do

    %w(near within approx).each do |operator|
      context "with #{operator}" do
        let(:source) { "{% with_scope f.#{operator}: [1, 2] %}42{% endwith_scope %}" }
        it { expect { output }.to raise_error(::Liquid::SyntaxError) }
      end
    end

  end

  describe 'the removed all operand form' do

    let(:source) { %q({% with_scope categories.all: "$and: ['A', 'B']" %}42{% endwith_scope %}) }

    it { expect { output }.to raise_error(::Liquid::SyntaxError, /Invalid value for categories\.all/) }

    context 'the same text handed over at render time' do

      let(:assigns) { { 'my_filters' => { 'categories.all' => "$and: ['A']" } } }
      let(:source)  { '{% with_scope my_filters %}{% assign conditions = with_scope %}{% endwith_scope %}' }

      it 'stays an ordinary value the tag does not read' do
        output
        expect(conditions['categories.all']).to eq "$and: ['A']"
      end

    end

  end

  describe 'a criterion handed over at render time' do

    let(:source) { '{% with_scope my_filters %}42{% endwith_scope %}' }

    { 'an operator the tag does not offer'  => { 'price.eq' => 1 },
      'a removed operator'                  => { 'price.near' => 1 },
      'a raw Mongo operator'                => { '$where' => 'sleep(1)' },
      'a nested field path'                 => { 'address.location.ne' => 1 },
      'a raw Mongo operator inside a value'  => { 'price' => { '$gt' => 1 } } }.each do |what, filters|

      context what do
        let(:assigns) { { 'my_filters' => filters } }
        it { expect { output }.to raise_error(::Liquid::SyntaxError) }
      end
    end

    context 'an operator the tag does offer' do
      let(:assigns) { { 'my_filters' => { 'price.gte' => 1 } } }
      it { expect { output }.not_to raise_error }
    end

    context 'one field named twice under different spellings' do
      let(:assigns) { { 'my_filters' => { :a => 1, 'a' => 2 } } }
      it { expect { output }.to raise_error(::Liquid::SyntaxError) }
    end

    context 'a key named twice inside a value' do
      let(:assigns) { { 'my_filters' => { 'payload' => { :a => 1, 'a' => 2 } } } }
      it { expect { output }.to raise_error(::Liquid::SyntaxError) }
    end

    context 'a field named twice, once by its old name' do
      let(:assigns) { { 'my_filters' => { '_permalink' => 'x', '_slug' => 'y' } } }
      it { expect { output }.to raise_error(::Liquid::SyntaxError) }
    end

    context 'a value that is not a set of criteria at all' do
      let(:assigns) { { 'my_filters' => 'price.gte' } }
      it { expect { output }.to raise_error(::Liquid::SyntaxError) }
    end

  end

  describe 'a runtime value shaped like a regexp' do

    let(:assigns) { { 'my_regexp' => '/^Hello World/' } }
    let(:source) { "{% with_scope title: my_regexp %}{% assign conditions = with_scope %}{% endwith_scope %}" }

    it 'stays text' do
      output
      expect(conditions['title']).to eq '/^Hello World/'
    end

    context 'built by capture around a visitor parameter' do

      let(:assigns) { { 'params' => { 'd' => 'shoe' } } }
      let(:source) do
        "{% assign searched_words = params.d %}" \
        "{% capture filter_query %}/{{ searched_words }}/i{% endcapture %}" \
        "{% with_scope name: filter_query %}{% assign conditions = with_scope %}{% endwith_scope %}"
      end

      it 'stays text' do
        output
        expect(conditions['name']).to eq '/shoe/i'
      end

    end

    context 'a real Regexp handed over from the host inside a criteria hash' do

      let(:assigns) { { 'my_filters' => { 'title' => /^hello world/ix } } }
      let(:source)  { '{% with_scope my_filters %}{% assign conditions = with_scope %}{% endwith_scope %}' }

      it 'passes as a typed value' do
        output
        expect(conditions['title']).to eq(/^hello world/ix)
      end

    end

  end

  describe 'a quoted string shaped like a regexp' do

    let(:source) { "{% with_scope title: '/foo/i' %}42{% endwith_scope %}" }

    it { expect { output }.to raise_error(::Liquid::SyntaxError, /must be a literal/) }

  end

  describe 'valid syntax' do

    before { output }

    describe 'renders basic stuff' do
      let(:source) { '{% with_scope a: 1 %}42{% endwith_scope %}' }
      it { expect(output).to eq '42' }
    end

    describe 'store the conditions in the context' do

      let(:source) { "{% with_scope active: true, price: 42, title: 'foo', hidden: false %}{% assign conditions = with_scope %}{% assign content_type = with_scope_content_type %}{% endwith_scope %}" }

      it { expect(context['conditions'].keys).to eq(%w(active price title hidden)) }
      it { expect(context['content_type']).to eq false }

    end

    describe 'pass directly a hash built with the Action liquid tag for example' do

      let(:assigns) { { 'my_filters' => { active: true, price: 42, title: '/like this/ix', hidden: false } } }

      let(:source)  { "{% with_scope my_filters %}{% assign conditions = with_scope %}{% assign content_type = with_scope_content_type %}{% endwith_scope %}" }

      it { expect(context['conditions'].keys).to eq(%w(active price title hidden)) }
      it { expect(conditions['active']).to eq true }
      it { expect(conditions['title']).to eq '/like this/ix' }

      context "the variable doesn't exist" do

        let(:assigns) { { } }
        it { expect(context['conditions']).to eq({}) }

      end

    end

    describe 'don\'t decode numeric operations' do
      let(:source) { "{% with_scope price: 41 + 1 %}{% assign conditions = with_scope %}{% endwith_scope %}" }
      it { expect(conditions['price']).to eq 41 }

      context 'the operation calls a variable' do
        let(:assigns) { { 'prices' => { 'low' => 41 } } }
        let(:source) { "{% with_scope price: prices.low + 1 %}{% assign conditions = with_scope %}{% endwith_scope %}" }
        it { expect(conditions['price']).to eq 41 }
      end
    end

    describe 'decode a deeply nested variable' do
      # A multi-segment dotted path resolves to its value in the scope condition.
      let(:assigns) { { 'params' => { 'a' => { 'b' => 'deep' } } } }
      let(:source)  { "{% with_scope foo: params.a.b %}{% assign conditions = with_scope %}{% endwith_scope %}" }
      it { expect(conditions['foo']).to eq 'deep' }
    end

    describe 'decode basic options (boolean, integer, ...)' do

      let(:source) { "{% with_scope active: true, price: 42, title: 'foo', hidden: false %}{% assign conditions = with_scope %}{% endwith_scope %}" }

      it { expect(conditions['active']).to eq true }
      it { expect(conditions['price']).to eq 42 }
      it { expect(conditions['title']).to eq 'foo' }
      it { expect(conditions['hidden']).to eq false }

    end
    
    describe 'decode regexps' do

      let(:source) { "{% with_scope title: /Like this one|or this one/ %}{% assign conditions = with_scope %}{% endwith_scope %}" }
      it { expect(conditions['title']).to eq(/Like this one|or this one/) }

    end

    describe 'decode regexps with case-insensitive' do

      let(:source) { "{% with_scope title: /like this/ix %}{% assign conditions = with_scope %}{% endwith_scope %}" }
      it { expect(conditions['title']).to eq(/like this/ix) }

    end

    describe 'decode content entry' do

      let(:entry) {
        instance_double('ContentEntry', _id: 1, _source: 'entity').tap do |_entry|
          allow(_entry).to receive(:to_liquid).and_return(_entry)
        end }
      let(:assigns) { { 'my_project' => entry } }
      let(:source)  { "{% with_scope project: my_project %}{% assign conditions = with_scope %}{% endwith_scope %}" }

      it { expect(conditions['project']).to eq 'entity' }

      context 'an array of content entries' do

        let(:source) { "{% with_scope project: [my_project, my_project, my_project] %}{% assign conditions = with_scope %}{% endwith_scope %}" }

        it { expect(conditions['project']).to eq ['entity', 'entity', 'entity'] }

      end

    end

    describe 'decode context variable' do

      let(:assigns) { { 'params' => { 'type' => 'posts' } } }
      let(:source) { "{% with_scope category: params.type %}{% assign conditions = with_scope %}{% endwith_scope %}" }
      it { expect(conditions['category']).to eq 'posts' }

    end

    describe 'allow order_by option' do

      let(:source) { "{% with_scope order_by:\'name DESC\' %}{% assign conditions = with_scope %}{% endwith_scope %}" }
      it { expect(conditions['order_by']).to eq 'name DESC' }

    end

    describe 'replace _permalink by _slug' do

      let(:source) { "{% with_scope _permalink: 'foo' %}{% assign conditions = with_scope %}{% endwith_scope %}" }
      it { expect(conditions['_slug']).to eq 'foo' }

    end

    describe 'decode criteria with gt and lt' do

      let(:source) { "{% with_scope price.gt: 42.0, price.lt:50, published_at.lte: '2019-09-10 00:00:00', published_at.gte: '2019/09/09 00:00:00' %}{% assign conditions = with_scope %}{% endwith_scope %}" }
      it { expect(conditions['price.gt']).to eq 42.0 }
      it { expect(conditions['price.lt']).to eq 50 }
      it { expect(conditions['published_at.lte']).to eq '2019-09-10 00:00:00' }
      it { expect(conditions['published_at.gte']).to eq '2019/09/09 00:00:00' }

    end

    describe 'decode the exists operator' do

      let(:source) { "{% with_scope f.exists: true %}{% assign conditions = with_scope %}{% endwith_scope %}" }
      it { expect(conditions['f.exists']).to eq true }

    end

    describe 'In a loop context, each scope should be evaluated correctly' do
      let(:assigns) { {'list' => ['A', 'B', 'C']} }
      let(:source) { "{% for key in list %}{% with_scope foo: key %}{% assign conditions = with_scope %}{% endwith_scope %}{{ conditions }}{% endfor %}" }

      # hashes are serialized by Liquid::Utils.to_s, no matter the Ruby version
      it { expect(output).to eq '{"foo"=>"A"}{"foo"=>"B"}{"foo"=>"C"}' }

    end

    describe 'a select option in a loop' do
      let(:options) do
        %w(grunge rock country).map do |name|
          Locomotive::Steam::Liquid::ContentTypeFieldSelectOption.new(OpenStruct.new(_id: name, name: name))
        end
      end
      let(:assigns) { { 'list' => options } }
      let(:source)  { "{% for opt in list %}{% with_scope kind: opt %}{% assign conditions = with_scope %}{% endwith_scope %}{{ conditions }}{% endfor %}" }

      it 'captures each option name independently' do
        expect(output).to eq '{"kind"=>"grunge"}{"kind"=>"rock"}{"kind"=>"country"}'
      end
    end

  end

  describe 'decode advanced options' do
    let(:options)  { "" }
    let(:source) { "{% with_scope key: #{options} %}{% assign conditions = with_scope %}{% endwith_scope %}" }

    before { output }
   
    context "Array" do
      context "of Integer" do
        let(:options)  { "[1, 2, 3]" }
        it { expect(conditions['key']).to eq [1, 2, 3] }
      end

      context "of String" do
        let(:options)  { "['a', 'b', 'c']" }
        it { expect(conditions['key']).to eq ['a', 'b', 'c'] }
      end

      context "With variable" do
        let(:assigns) { {'a' => 1, 'c' => 3} }
        let(:options) { "[a, 2, c, 'd']" }
        it { expect(conditions['key']).to eq [1, 2, 3, 'd'] }
      end
    end

    context "Hash" do
      context "With key value" do
        let(:options)  { "{a: 1, b: 2, c: 3, d: 'foo'}" }
        it { expect(conditions['key'].keys).to eq(%w(a b c d)) }
        it { expect(conditions['key']['a']).to eq 1 }
        it { expect(conditions['key']['b']).to eq 2 }
        it { expect(conditions['key']['c']).to eq 3 }
        it { expect(conditions['key']['d']).to eq 'foo' }
      end

      context "With key variable" do
        let(:assigns) { {'a' => 1, 'c' => 3} }
        let(:options)  { "{a: a, b: 2, c: c, d: 'foo'}" }
        it { expect(conditions['key'].keys).to eq(%w(a b c d)) }
        it { expect(conditions['key']['a']).to eq 1 }
        it { expect(conditions['key']['b']).to eq 2 }
        it { expect(conditions['key']['c']).to eq 3 }
        it { expect(conditions['key']['d']).to eq 'foo' }
      end

      context "With params" do
        let(:assigns) { { 'params' => Locomotive::Steam::Liquid::Drops::Params.new({ foo: 'bar' }) } }
        let(:options)  { "{'a': params.foo}" }
        it { expect(conditions['key'].keys).to eq(%w(a)) }
        it { expect(conditions['key']['a']).to eq 'bar' }
      end
    end
  end
end
