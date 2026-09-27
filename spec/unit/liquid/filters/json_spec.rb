require 'spec_helper'

describe Locomotive::Steam::Liquid::Filters::Json do

  include Locomotive::Steam::Liquid::Filters::Json

  let(:input) { nil }
  subject     { json(*input) }

  describe 'adds quotes to a string' do

    let(:input) { 'foo' }
    it { expect(subject).to eq %("foo") }

  end

  context 'drop' do

    describe 'includes only the fields specified' do

      let(:input) { [Liquid::TestDrop.new(title: 'Acme', body: 'Lorem ipsum'), 'title'] }
      it { expect(subject).to eq %({"title":"Acme"}) }

    end

  end

  context 'collections' do

    describe 'adds brackets and quotes to a collection' do

      let(:input) { [['foo', 'bar']] }
      it { expect(subject).to eq %(["foo","bar"]) }

    end

    describe 'includes the first field' do

      let(:input) {
        [[Liquid::TestDrop.new(title: 'Acme', body: 'Lorem ipsum'),
          Liquid::TestDrop.new(title: 'Hello world', body: 'Lorem ipsum')], 'title'] }
      it { expect(subject).to eq %(["Acme","Hello world"]) }

    end

    describe 'includes the specified fields' do

      let(:input) {
        [[Liquid::TestDrop.new(title: 'Acme', body: 'Lorem ipsum', date: '2013-12-13'),
          Liquid::TestDrop.new(title: 'Hello world', body: 'Lorem ipsum', date: '2013-12-12')], 'title, body'] }
      it { expect(subject).to eq %([{"title":"Acme","body":"Lorem ipsum"},{"title":"Hello world","body":"Lorem ipsum"}]) }

    end

  end

  describe '#Render Hash' do

    let(:input) { [{'foo': 'bar'}] }
    it { expect(subject).to eq %({"foo":"bar"}) }

  end

  describe 'scalars and objects' do

    it { expect(json(42)).to eq '42' }
    it { expect(json(nil)).to eq 'null' }
    it { expect(json(Time.utc(2026, 9, 27, 10))).to eq %("2026-09-27T10:00:00.000Z") }

    it 'renders a file through its hash' do
      file = Locomotive::Steam::ContentEntry::FileField.new('a.png', '/files', 1, nil)

      expect(json(file)).to eq %({"url":"/files/a.png","filename":"a.png","size":1,"updated_at":null})
    end

    it 'opens the json it renders' do
      output = Liquid::Template.parse('{{ h | json | open_json }}').render!('h' => { 'a' => 1, 'b' => 'x' })

      expect(output).to eq %("a":1,"b":"x")
    end

    it 'escapes markup and line separators in a string' do
      expect(json("</script>&\u2028")).to eq %("\\u003c/script\\u003e\\u0026\\u2028")
    end

  end

  describe 'inside an HTML script element' do

    let(:text) { "</script><!--&\u2028\u2029" }

    around do |example|
      encoding   = ActiveSupport::JSON::Encoding
      entities   = encoding.escape_html_entities_in_json
      separators = encoding.escape_js_separators_in_json

      encoding.escape_html_entities_in_json = false
      encoding.escape_js_separators_in_json = false
      example.run
    ensure
      encoding.escape_html_entities_in_json = entities
      encoding.escape_js_separators_in_json = separators
    end

    def expect_script_safe(output, value)
      expect(output).not_to match(/[<>&\u2028\u2029]/)
      expect(JSON.parse(output)).to eq value
    end

    it('escapes a string') { expect_script_safe(json(text), text) }
    it('escapes a hash')   { expect_script_safe(json({ 'x' => text }), { 'x' => text }) }
    it('escapes a list')   { expect_script_safe(json([text, 'b']), [text, 'b']) }

    it 'escapes the fields taken from a drop' do
      expect_script_safe(json(Liquid::TestDrop.new(title: text, body: 'b'), 'title'), { 'title' => text })
    end

    it 'escapes a collection by one field or by several' do
      drops = [Liquid::TestDrop.new(title: text, body: 'b'), Liquid::TestDrop.new(title: 'c', body: text)]

      expect_script_safe(json(drops, 'title'), [text, 'c'])
      expect_script_safe(json(drops, 'title, body'), [{ 'title' => text, 'body' => 'b' }, { 'title' => 'c', 'body' => text }])
    end

    it 'escapes a file' do
      file = Locomotive::Steam::ContentEntry::FileField.new(text, '/files', 1, nil)

      expect_script_safe(json(file), { 'url' => "/files/#{text}", 'filename' => text, 'size' => 1, 'updated_at' => nil })
    end

    it 'keeps a rendered script element closed only where the template closes it' do
      html = Liquid::Template.parse('<script>var x = {{ x | json }};</script>').render!('x' => { 'a' => text })

      expect(html.scan('</script>').size).to eq 1
      expect(html).to end_with '</script>'
      expect(JSON.parse(html[/var x = (.*);<\/script>/m, 1])).to eq({ 'a' => text })
    end

    it 'escapes what open_json takes out of it' do
      output = Liquid::Template.parse('{{ h | json | open_json }}').render!('h' => { 'a' => text })

      expect_script_safe("{#{output}}", { 'a' => text })
    end

  end

  describe '#open_json' do

    let(:input) { '' }
    subject     { open_json(input) }

    it { expect(subject).to eq '' }

    context 'without leading and trailing brackets' do

      let(:input) { %(["foo",[1,2],"bar"]) }
      it { expect(subject).to eq %("foo",[1,2],"bar") }

    end

    context 'without leading and trailing braces' do

      let(:input) { %({"title":"Acme","body":"Lorem ipsum"}) }
      it { expect(subject).to eq %("title":"Acme","body":"Lorem ipsum") }

    end

  end

end
