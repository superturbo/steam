require 'spec_helper'

require_relative '../../../../lib/locomotive/steam/adapters/query'

describe Locomotive::Steam::Adapters::Query::OrderBy do

  let(:invalid)     { Locomotive::Steam::Adapters::Query::InvalidValue }
  let(:unsupported) { Locomotive::Steam::Adapters::Query::UnsupportedOperator }

  def decode(*spec)
    described_class.decode(*spec)
  end

  describe '.decode' do

    it('a bare field defaults to asc') { expect(decode('name')).to eq [[:name, :asc]] }
    it('a dotted direction') { expect(decode('name.desc')).to eq [[:name, :desc]] }
    it('a spaced direction') { expect(decode('name desc')).to eq [[:name, :desc]] }
    it('a piped direction') { expect(decode('name|desc')).to eq [[:name, :desc]] }
    it('is case-insensitive') { expect(decode('name.DESC')).to eq [[:name, :desc]] }

    it 'a comma-separated list' do
      expect(decode('name.desc, created_at.asc')).to eq [[:name, :desc], [:created_at, :asc]]
    end

    it('a Hash with a string direction') { expect(decode(name: 'asc')).to eq [[:name, :asc]] }
    it('a Hash with 1/-1') { expect(decode(name: 1, position: -1)).to eq [[:name, :asc], [:position, :desc]] }
    it('a Hash with a symbol direction') { expect(decode(name: :desc)).to eq [[:name, :desc]] }

    it('two symbol args form a single pair') { expect(decode(:name, :desc)).to eq [[:name, :desc]] }
    it('a field-only array') { expect(decode(['_position'])).to eq [[:_position, :asc]] }

    it 'a flat array is a list of criteria' do
      expect(decode(['name', 'created_at'])).to eq [[:name, :asc], [:created_at, :asc]]
    end

    it 'multiple string args are a list of criteria' do
      expect(decode('name', 'created_at')).to eq [[:name, :asc], [:created_at, :asc]]
    end

    it 'an array of criterion strings' do
      expect(decode(['title.asc', 'published'])).to eq [[:title, :asc], [:published, :asc]]
    end

    it 'a nested array is a list of pairs' do
      expect(decode([['name', 'desc'], ['created_at', 'asc']])).to eq [[:name, :desc], [:created_at, :asc]]
    end

    it 'a deeply nested array of pairs' do
      expect(decode([[['title', 'asc'], ['published', 'desc']]])).to eq [[:title, :asc], [:published, :desc]]
    end

    it('nil is dropped') { expect(decode(nil)).to eq [] }
    it('an empty array is dropped') { expect(decode([])).to eq [] }

    it 'rejects an unknown direction' do
      expect { decode('name.sideways') }.to raise_error(invalid)
    end

    it 'rejects a numeric direction other than 1 or -1' do
      expect { decode(name: 2) }.to raise_error(invalid)
    end

    it 'rejects an empty field name' do
      expect { decode('name,,other') }.to raise_error(invalid)
    end

    it 'validates the direction of a nested pair' do
      expect { decode([['name', 'sideways']]) }.to raise_error(invalid)
    end

    it 'rejects a nested pair with too many elements' do
      expect { decode([['name', 'asc', 'extra']]) }.to raise_error(invalid)
    end

    it 'rejects a written criterion with too many tokens' do
      ['name asc desc', 'name.asc.desc', 'name|asc|desc', 'title desc, name asc desc']
        .each { |spec| expect { decode(spec) }.to raise_error(invalid) }
    end

    it 'rejects a field named twice, whatever the directions' do
      ['score.asc, score.desc', 'score.desc, score.asc', 'score, score'].each do |spec|
        expect { decode(spec) }.to raise_error(invalid, /duplicate order field: :score/)
      end
    end

    it 'rejects a field named twice across separate criteria' do
      expect { decode('name', 'name.desc') }.to raise_error(invalid)
      expect { decode(['name', 'name.desc']) }.to raise_error(invalid)
      expect { decode([['name', 'asc'], ['name', 'desc']]) }.to raise_error(invalid)
      expect { decode(name: :asc, 'name' => :desc) }.to raise_error(invalid)
    end

    it 'rejects a $-prefixed field on both engines' do
      expect { decode('$natural') }.to raise_error(unsupported)
      expect { decode('$where' => 1) }.to raise_error(unsupported)
    end

    it 'does not mutate its input' do
      spec = { title: :asc }
      decode(spec)
      expect(spec).to eq(title: :asc)
    end

  end

end
