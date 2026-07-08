require 'spec_helper'

describe Locomotive::Steam::Liquid::MarshalCache do

  let(:source)   { 'Hello {% if visible %}world{% endif %} {{ name | upcase }}' }
  let(:options)  { { page: instance_double('Page'), parser: instance_double('Parser') } }
  let(:template) { Locomotive::Steam::Liquid::Template.parse(source, options) }
  let(:assigns)  { { 'visible' => true, 'name' => 'joe' } }

  subject(:loaded) { Marshal.load(Marshal.dump(template)) }

  it 'renders the same output after a Marshal round trip' do
    expect(loaded.render(assigns)).to eq template.render(assigns)
  end

  it 'drops the service objects from the parse options' do
    tag = loaded.root.nodelist.find { |node| node.respond_to?(:parse_context) }
    expect(tag.parse_context[:parser]).to eq nil
    expect(tag.parse_context[:page]).to eq nil
  end

  it 'rebuilds the parse-time machinery so render-time re-parsing works' do
    tag           = loaded.root.nodelist.find { |node| node.respond_to?(:parse_context) }
    parse_context = tag.parse_context

    expect(parse_context.environment).to eq ::Liquid::Environment.default
    expect(parse_context.instance_variable_get(:@string_scanner)).to be_a(StringScanner)
    expect { parse_context.new_parser('a > b') }.not_to raise_error
  end

  context 'a snippet parsed at render time (the PartialCache path)' do

    let(:source)      { "Hello {% include 'footer' %}" }
    let(:file_system) { instance_double('FileSystem') }

    before do
      allow(file_system).to receive(:read_template_file).with('footer').and_return('<footer>ok</footer>')
    end

    it 'renders the partial from a marshal-loaded template' do
      context = ::Liquid::Context.new({}, {}, { file_system: file_system })
      expect(loaded.render(context)).to eq 'Hello <footer>ok</footer>'
    end

  end

  context 'a template parsed against a custom Liquid environment' do

    let(:custom_environment) { ::Liquid::Environment.build(error_mode: :strict) }
    let(:template) { ::Liquid::Template.parse(source, environment: custom_environment) }

    it 'deliberately rebinds to the default environment on load' do
      expect(loaded.instance_variable_get(:@environment)).to eq ::Liquid::Environment.default
    end

  end

end
