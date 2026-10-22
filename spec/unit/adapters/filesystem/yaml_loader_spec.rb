require 'spec_helper'

require_relative '../../../../lib/locomotive/steam/adapters/filesystem/yaml_loader.rb'
require_relative '../../../../lib/locomotive/steam/errors.rb'

describe Locomotive::Steam::Adapters::Filesystem::YAMLLoader do

  let(:host)   { Class.new { include Locomotive::Steam::Adapters::Filesystem::YAMLLoader } }
  let(:loader) { host.new('/site') }

  describe '#safe_yaml_load' do

    def load(yaml, &block)
      loader.safe_yaml_load(yaml, nil, 'data/topics.yml', &block)
    end

    it 'reads a list of entries as a data file holds it' do
      expect(load("- name: A\n- name: B\n")).to eq [{ name: 'A' }, { name: 'B' }]
    end

    it 'reads a value a data file holds on its own' do
      expect([load("42\n"), load("plain text\n")]).to eq [42, 'plain text']
    end

    it 'reads a key written as a symbol' do
      expect(load(":name: A\n")).to eq(name: 'A')
    end

    ["1: value\n", "topic:\n  true: value\n", "- name: A\n- 2.5: B\n"].each do |yaml|
      it "refuses #{yaml.inspect}, whose keys are not all text, with its path" do
        expect { load(yaml) }.to raise_error('Malformed YAML in this file data/topics.yml, error: every key must be text')
      end
    end

    it 'leaves what the block raises as it is' do
      [StandardError.new('from the caller'), Interrupt.new].each do |raised|
        expect { load("name: A\n") { raise raised } }.to raise_error { |error| expect(error).to equal raised }
      end
    end

  end

  describe '#safe_json_load' do

    subject { loader.safe_json_load(json, nil, 'page.json') }

    context 'an object' do
      let(:json) { '{"a":1}' }
      it { is_expected.to eq('a' => 1) }
    end

    context 'a list' do
      let(:json) { '[1, 2]' }
      it { is_expected.to eq [1, 2] }
    end

    context 'an empty file' do
      let(:json) { '' }
      it { is_expected.to eq({}) }
    end

    context 'null' do
      let(:json) { 'null' }
      it { is_expected.to be_nil }
    end

    context 'a value JSON can hold on its own' do
      let(:json) { '42' }
      it { is_expected.to eq 42 }
    end

    context 'a name given twice' do
      let(:json) { '{"a":1,"a":2}' }
      it { expect { subject }.to raise_error(Locomotive::Steam::JsonParsingError) }
    end

    context 'notes around the value' do
      let(:json) { "// why\n{\"a\":1}" }
      it { expect { subject }.to raise_error(Locomotive::Steam::JsonParsingError) }

      context 'inside it' do
        let(:json) { '{"a":1 /* one */}' }
        it { expect { subject }.to raise_error(Locomotive::Steam::JsonParsingError) }
      end
    end

    context 'text no JSON can be read from' do
      let(:json) { '{ not valid json }' }
      it { expect { subject }.to raise_error(Locomotive::Steam::JsonParsingError) }
    end

    context 'text after the value' do
      let(:json) { '{"a":1} oops' }
      it { expect { subject }.to raise_error(Locomotive::Steam::JsonParsingError) }
    end

    %w(NaN Infinity).each do |literal|
      context "a number JSON cannot spell, #{literal}" do
        let(:json) { %({"a":#{literal}}) }
        it { expect { subject }.to raise_error(Locomotive::Steam::JsonParsingError) }
      end
    end

    context 'text no encoding can read' do
      let(:json) { %({"a":"\xFF"}) }

      it { expect { subject }.to raise_error(Locomotive::Steam::JsonParsingError) }
    end

    context 'given a block' do
      let(:json) { '{"a":1}' }

      it 'hands it what was read' do
        seen = nil
        loader.safe_json_load(json, 'template', 'page.json') { |attributes, template| seen = [attributes, template] }

        expect(seen).to eq [{ 'a' => 1 }, 'template']
      end
    end

  end

end
