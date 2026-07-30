require 'spec_helper'

require_relative '../../../../lib/locomotive/steam/adapters/mongodb/query_compiler.rb'

describe Locomotive::Steam::Adapters::MongoDB::QueryCompiler do

  let(:aliases)     { { 'title' => 'title.en' } }
  let(:compiler)    { described_class.new(aliases) }
  let(:unsupported) { Locomotive::Steam::Adapters::Query::UnsupportedOperator }
  let(:invalid)     { Locomotive::Steam::Adapters::Query::InvalidValue }

  def filter(criteria)
    compiler.compile(criteria, sort: nil, fields: nil, skip: nil, limit: nil).filter
  end

  describe '#compile filter — operator expansion' do
    it { expect(filter('price.gt'  => 5)).to   eq('price'  => { '$gt'  => 5 }) }
    it { expect(filter('price.gte' => 5)).to   eq('price'  => { '$gte' => 5 }) }
    it { expect(filter('price.lt'  => 5)).to   eq('price'  => { '$lt'  => 5 }) }
    it { expect(filter('price.lte' => 5)).to   eq('price'  => { '$lte' => 5 }) }
    it { expect(filter('handle.ne' => nil)).to eq('handle' => { '$ne'  => nil }) }
    it { expect(filter('handle.==' => 'a')).to eq('handle' => { '$eq'  => 'a' }) }
  end

  describe '#compile filter — list operators normalise the value to an array' do
    it { expect(filter('tags.in'  => 'awesome')).to eq('tags' => { '$in'  => ['awesome'] }) }
    it { expect(filter('tags.in'  => [1, 2])).to    eq('tags' => { '$in'  => [1, 2] }) }
    it { expect(filter('tags.in'  => Set[1, 2])).to eq('tags' => { '$in'  => [1, 2] }) }
    it { expect(filter('type.nin' => :x)).to        eq('type' => { '$nin' => [:x] }) }
    it { expect(filter('tags.all' => %w(a b))).to   eq('tags' => { '$all' => %w(a b) }) }
    it { expect { filter('tags.in' => (1..3)) }.to raise_error(invalid) }
  end

  describe '#compile filter — plain fields' do
    it { expect(filter(handle: 'acme')).to eq('handle' => 'acme') }
    it { expect(filter(published: true)).to eq('published' => true) }
    it { expect(filter(name: /bob/)).to eq('name' => /bob/) }
    it { expect(filter(price: (1..3))).to eq('price' => { '$gte' => 1, '$lte' => 3 }) }
    it { expect(filter(price: (1...3))).to eq('price' => { '$gte' => 1, '$lt' => 3 }) }
    it { expect(filter(price: (1..))).to eq('price' => { '$gte' => 1 }) }
    it { expect(filter(price: (..3))).to eq('price' => { '$lte' => 3 }) }
    it { expect(filter(price: (...3))).to eq('price' => { '$lt' => 3 }) }
    it { expect { filter(price: Range.new(nil, nil)) }.to raise_error(invalid) }
    it { expect(filter(tags: Set[1, 2])).to eq('tags' => [1, 2]) }
  end

  describe '#compile filter — localisation aliases' do
    it { expect(filter(title: 'Hi')).to eq('title.en' => 'Hi') }
    it { expect(filter('title.in' => %w(a b))).to eq('title.en' => { '$in' => %w(a b) }) }
  end

  describe '#compile filter — a dotted key needs a plain field and a known operator' do
    it 'rejects a nested field path' do
      expect { filter('address.location.ne' => 1) }.to raise_error(invalid)
    end
    it 'rejects a non-operator suffix' do
      expect { filter('meta.title' => 'x') }.to raise_error(unsupported)
    end
    it 'rejects an empty field' do
      expect { filter('' => 'x') }.to raise_error(invalid)
      expect { filter('.ne' => 'x') }.to raise_error(invalid)
    end
  end

  describe '#compile filter — $exists cast' do
    it { expect(filter('f.exists' => true)).to      eq('f' => { '$exists' => true }) }
    it { expect(filter('f.exists' => false)).to     eq('f' => { '$exists' => false }) }
    it { expect(filter('f.exists' => 'true')).to    eq('f' => { '$exists' => true }) }
    it { expect(filter('f.exists' => 'false')).to   eq('f' => { '$exists' => false }) }
    it { expect { filter('f.exists' => 'company') }.to raise_error(invalid) }
  end

  describe '#compile filter — $size cast' do
    it { expect(filter('tags.size' => 2)).to   eq('tags' => { '$size' => 2 }) }
    it { expect(filter('tags.size' => '2')).to eq('tags' => { '$size' => 2 }) }

    it 'raises rather than truncate a fractional value' do
      expect { filter('tags.size' => 2.5) }.to raise_error(invalid)
    end

    it 'raises on a non-integer' do
      expect { filter('tags.size' => 'x') }.to raise_error(invalid)
    end

    it 'raises on a negative value' do
      expect { filter('tags.size' => -1) }.to raise_error(invalid)
    end
  end

  describe '#compile filter — $and structure' do
    it { expect(filter(handle: 'acme')).to eq('handle' => 'acme') }

    it 'combines several criteria under $and' do
      expect(filter('price.gte' => 1, 'price.lte' => 3)).to eq(
        '$and' => [{ 'price' => { '$gte' => 1 } }, { 'price' => { '$lte' => 3 } }]
      )
    end

    it { expect(filter({})).to eq({}) }
  end

  describe '#compile filter — any operator outside the registry raises' do
    %w(neq not mod near within approx).each do |op|
      it "raises UnsupportedOperator for #{op}" do
        expect { filter("f.#{op}" => 1) }.to raise_error(unsupported)
      end
    end
  end

  describe '#compile filter — rejects Mongo operator injection' do
    context 'in the key' do
      it { expect { filter('$where' => 'sleep(1000)') }.to raise_error(unsupported) }
      it { expect { filter('$or' => [{ a: 1 }]) }.to raise_error(unsupported) }
      it { expect { filter('$expr' => {}) }.to raise_error(unsupported) }
      it { expect { filter('field.$gt' => 5) }.to raise_error(unsupported) }
    end

    context 'in a Hash value (recursively, through Array and Set)' do
      it { expect { filter(price: { '$gt' => 5 }) }.to raise_error(unsupported) }
      it { expect { filter(name: { '$not' => { '$regex' => 'bob' } }) }.to raise_error(unsupported) }
      it { expect { filter(tags: [{ '$where' => 'x' }]) }.to raise_error(unsupported) }
      it { expect { filter('tags.in' => Set[{ '$gt' => 5 }]) }.to raise_error(unsupported) }
    end

    it 'still allows a legitimate sub-document equality match, with String keys' do
      expect(filter(address: { city: 'x' })).to eq('address' => { 'city' => 'x' })
    end
  end

  describe '#compile filter — value types are delegated to BSON' do
    it 'leaves a Date for the driver to serialize' do
      date = Date.new(2020, 1, 15)
      expect(filter('d.lte' => date)).to eq('d' => { '$lte' => date })
    end

    it 'leaves a Time for the driver to serialize' do
      time = Time.utc(2020, 1, 15, 10, 30)
      expect(filter('t.gt' => time)).to eq('t' => { '$gt' => time })
    end

    it 'leaves a BigDecimal for the driver to serialize' do
      amount = BigDecimal('1.5')
      expect(filter('n.gt' => amount)).to eq('n' => { '$gt' => amount })
    end
  end

  describe '#compile — does not mutate its inputs' do
    it 'leaves the criteria hash and its array values untouched' do
      values   = [1, 2]
      criteria = { 'tags.in' => values }
      compiler.compile(criteria, sort: nil, fields: nil, skip: nil, limit: nil)
      expect(criteria).to eq('tags.in' => [1, 2])
      expect(values).to eq([1, 2])
    end

    it 'leaves the sort spec untouched' do
      spec = [[:title, :asc]]
      compiler.compile({}, sort: spec, fields: nil, skip: nil, limit: nil)
      expect(spec).to eq([[:title, :asc]])
    end
  end

  describe '#compile options — sort (neutral [[field, dir]] form)' do
    def sort(spec)
      compiler.compile({}, sort: spec, fields: nil, skip: nil, limit: nil).options[:sort]
    end

    it { expect(sort([[:title, :asc], [:published, :desc]])).to eq('title.en' => 1, 'published' => -1) }
    it { expect(sort([[:date, :desc]])).to eq('date' => -1) }
    it { expect(sort([[:_position, :asc]])).to eq('_position' => 1) }
    it { expect(sort(nil)).to be_nil }
    it { expect(sort([])).to be_nil }

    it 'rejects a $-prefixed field such as $natural' do
      expect { sort([[:'$natural', :asc]]) }.to raise_error(unsupported)
    end
  end

  describe '#compile options — projection' do
    def projection(list)
      compiler.compile({}, sort: nil, fields: list, skip: nil, limit: nil).options[:projection]
    end

    it { expect(projection([:title, :published])).to eq('title.en' => 1, 'published' => 1) }
    it { expect(projection(nil)).to be_nil }

    it 'rejects a $-prefixed field' do
      expect { projection(['$natural']) }.to raise_error(unsupported)
    end
  end

  describe '#compile options — assembly' do
    it 'passes skip and limit and drops absent options' do
      expect(compiler.compile({}, sort: nil, fields: nil, skip: 5, limit: 10).options).to eq(skip: 5, limit: 10)
    end

    it 'is empty when nothing is set' do
      expect(compiler.compile({}, sort: nil, fields: nil, skip: nil, limit: nil).options).to eq({})
    end
  end

end
