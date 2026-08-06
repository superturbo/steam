require 'spec_helper'

describe Locomotive::Steam::ContentFieldValues do

  describe 'what a refused value reports' do

    { 'text that reads as no number'  => [[:integer, '12x'],           :invalid_number],
      'a number past the bounds'      => [[:integer, 2**63],           :outside_numeric_bounds],
      'text past the bounds'          => [[:integer, '9' * 20],        :outside_numeric_bounds],
      'a value of another type'       => [[:integer, [1]],             :wrong_type],
      'text that reads as no boolean' => [[:boolean, 'yes'],           :invalid_boolean],
      'a number where a boolean goes' => [[:boolean, 2],               :wrong_type],
      'text that reads as no date'    => [[:date, 'someday'],          :invalid_date],
      'text that reads as no JSON'    => [[:json, '{oops'],            :invalid_json],
      'a value JSON cannot hold'      => [[:json, { 'v' => :sym }],    :invalid_json_value],
      'a name JSON cannot use'        => [[:json, { 1 => 'x' }],       :invalid_json_name],
      'text in no readable encoding'  => [[:string, %(caf\xFF)],       :invalid_encoding]
    }.each do |label, ((type, value), reason)|
      it "reports #{reason} for #{label}" do
        expect { described_class.normalize_input(type, value) }
          .to raise_error(described_class::ParseError) { |error| expect(error.reason).to eq reason }
      end
    end

    it 'reports json_too_deep for an object nested past the limit' do
      value = (1..98).inject('n' => 1) { |inner, _| { 'n' => inner } }

      expect { described_class.normalize_input(:json, value) }
        .to raise_error(described_class::ParseError) { |error| expect(error.reason).to eq :json_too_deep }
    end

    it 'refuses a reason no rule declares' do
      expect { described_class::ParseError.new(:invalid_number, 'x') }.not_to raise_error
      expect { described_class::ParseError.new(:made_up, 'x') }.to raise_error(ArgumentError)
    end

    { 'a number field' => [:integer, '12x-marker'],
      'a date field'   => [:date, 'someday-marker'],
      'a JSON field'   => [:json, '{oops-marker'] }.each do |label, (type, value)|
      it "says nothing of the value #{label} refused" do
        expect { described_class.normalize_input(type, value) }
          .to raise_error(described_class::ParseError) { |error| expect(error.message).not_to include 'marker' }
      end
    end

    it 'says nothing of text it could not read' do
      expect { described_class.normalize_input(:string, "caf\xFF".dup.force_encoding('UTF-8')) }
        .to raise_error(described_class::ParseError) { |error| expect(error.message).not_to include 'caf' }
    end

    it 'names what JSON text turned out to be, not the text it came from' do
      expect { described_class.normalize_input(:json, '[1, 2]') }
        .to raise_error(described_class::ParseError, 'expected a JSON object, got Array')
    end

  end

  describe '#normalize_input of a text field' do

    subject { described_class.normalize_input(:string, value) }

    context 'written in another encoding' do
      let(:value) { "caf\xE9".dup.force_encoding('ISO-8859-1') }

      it 'is kept as the UTF-8 every store reads' do
        expect(subject.encoding).to eq Encoding::UTF_8
        expect(subject.bytes).to eq [99, 97, 102, 195, 169]
      end
    end

    context 'in no readable encoding' do
      let(:value) { "caf\xFF".dup.force_encoding('UTF-8') }
      it { expect { subject }.to raise_error(described_class::ParseError, /no readable encoding/) }
    end

  end

  describe '#normalize_input of a json field' do

    subject { described_class.normalize_input(:json, value) }

    context 'given an object' do

      let(:value) { { a: 1, 'b' => [2, { c: nil }] } }

      it { is_expected.to eq('a' => 1, 'b' => [2, { 'c' => nil }]) }

    end

    context 'given text' do

      let(:value) { ' {"a":[1,{"b":null}]} ' }

      it { is_expected.to eq('a' => [1, { 'b' => nil }]) }

      context 'that is blank' do
        let(:value) { '   ' }
        it { is_expected.to be_nil }
      end

      context 'in no readable encoding' do
        let(:value) { %({"a":"\xFF"}) }
        it { expect { subject }.to raise_error(described_class::ParseError, /no readable encoding/) }
      end

      context 'that never parses' do
        let(:value) { '{oops' }
        it { expect { subject }.to raise_error(described_class::ParseError, /invalid JSON/) }
      end

      context 'carrying notes' do
        let(:value) { '{"a":1 /* one */}' }
        it { expect { subject }.to raise_error(described_class::ParseError, /invalid JSON/) }
      end

    end

    {
      'a list'         => [1, 2, 3],
      'a number'       => 42,
      'a list in text' => '[1, 2, 3]'
    }.each do |label, given|
      context "given #{label} rather than an object" do
        let(:value) { given }
        it { expect { subject }.to raise_error(described_class::ParseError, /expected a JSON object/) }
      end
    end

    describe 'what a value may be' do

      let(:value) { { 'v' => inside } }

      { 'text'      => 'hello',
        'a number'  => 42,
        'a fraction' => 1.5,
        'true'      => true,
        'false'     => false,
        'nothing'   => nil,
        'a list'    => [1, 'two'],
        'an object' => { 'a' => 1 } }.each do |label, given|
        context label do
          let(:inside) { given }
          it { is_expected.to eq('v' => given) }
        end
      end

      { 'a moment'     => Time.utc(2020, 1, 1),
        'a day'        => Date.new(2020, 1, 1),
        'a symbol'     => :sym,
        'a set'        => Set.new([1]),
        'a decimal'    => BigDecimal('1.5') }.each do |label, given|
        context label do
          let(:inside) { given }
          it { expect { subject }.to raise_error(described_class::ParseError, /cannot be stored as JSON/) }
        end
      end

      context 'text in no readable encoding' do
        let(:inside) { %(a\xFF) }
        it { expect { subject }.to raise_error(described_class::ParseError, /no readable encoding/) }
      end

      context 'text written in another encoding' do
        let(:inside) { "caf\xE9".dup.force_encoding('ISO-8859-1') }

        it 'is kept as the UTF-8 every store reads' do
          expect(subject['v'].encoding).to eq Encoding::UTF_8
          expect(subject['v'].bytes).to eq [99, 97, 102, 195, 169]
        end
      end

      context 'text no encoding can turn into UTF-8' do
        let(:inside) { "caf\xE9".dup.force_encoding('ASCII-8BIT') }
        it { expect { subject }.to raise_error(described_class::ParseError, /no store can keep/) }
      end

      context 'a number past what a store writes down' do
        let(:inside) { 2**63 }
        it { expect { subject }.to raise_error(described_class::ParseError, /outside supported bounds/) }
      end

      context 'a fraction no store writes down' do
        let(:inside) { Float::INFINITY }
        it { expect { subject }.to raise_error(described_class::ParseError, /outside supported bounds/) }
      end

      context 'the largest number a store writes down' do
        let(:inside) { 2**63 - 1 }
        it { is_expected.to eq('v' => 2**63 - 1) }
      end

    end

    describe 'what may name a value' do

      let(:value) { { name => 1 } }

      context 'a symbol' do
        let(:name) { :a }
        it { is_expected.to eq('a' => 1) }
      end

      context 'anything else' do
        let(:name) { 1 }
        it { expect { subject }.to raise_error(described_class::ParseError, /cannot name a JSON value/) }
      end

      context 'text in no readable encoding' do
        let(:name) { %(a\xFF) }
        it { expect { subject }.to raise_error(described_class::ParseError, /no readable encoding/) }
      end

      context 'text holding a null character' do
        let(:name) { "a\u0000b" }
        it { expect { subject }.to raise_error(described_class::ParseError, /null character/) }
      end

      context 'a name given twice' do
        let(:value) { '{"a": 1, "a": 2}' }
        it { expect { subject }.to raise_error(described_class::ParseError, /invalid JSON/) }
      end

    end

    describe 'how deep it may go' do

      def nest(depth) = (1..depth - 1).inject('n' => 1) { |inner, _| { 'n' => inner } }
      def nest_in_text(depth) = ('{"n":' * depth) + '1' + ('}' * depth)

      context 'as an object' do
        context 'at the limit' do
          let(:value) { nest(98) }
          it { is_expected.to be_a(Hash) }
        end

        context 'one level past it' do
          let(:value) { nest(99) }
          it { expect { subject }.to raise_error(described_class::ParseError, /nested deeper/) }
        end
      end

      context 'as text' do
        context 'at the limit' do
          let(:value) { nest_in_text(98) }
          it { is_expected.to be_a(Hash) }
        end

        context 'one level past it' do
          let(:value) { nest_in_text(99) }
          it { expect { subject }.to raise_error(described_class::ParseError, /invalid JSON/) }
        end
      end

    end

    describe 'what the caller goes on holding' do

      context 'an object' do
        let(:value) { { 'a' => [1] } }

        it 'is copied, not taken' do
          subject['a'] << 2

          expect(value).to eq('a' => [1])
        end
      end

      context 'text inside an object' do
        let(:value) { { 'a' => +'hello' } }

        it 'is copied, not taken' do
          subject['a'] << ' there'

          expect(value).to eq('a' => 'hello')
        end
      end

      context 'one value reached by two names' do
        let(:shared) { { 'v' => 1 } }
        let(:value)  { { 'left' => shared, 'right' => shared } }

        it 'is copied into each' do
          subject['left']['v'] = 2

          expect(subject).to eq('left' => { 'v' => 2 }, 'right' => { 'v' => 1 })
        end
      end

    end

    describe 'a structure that contains itself' do

      context 'through a name' do
        let(:value) do
          loop_back = { 'a' => 1 }
          loop_back['self'] = loop_back
          loop_back
        end

        it { expect { subject }.to raise_error(described_class::ParseError, /nested deeper/) }
      end

      context 'through a list' do
        let(:value) do
          loop_back = { 'a' => [] }
          loop_back['a'] << loop_back
          loop_back
        end

        it { expect { subject }.to raise_error(described_class::ParseError, /nested deeper/) }
      end

    end

  end

end
