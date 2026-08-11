require 'spec_helper'

describe Locomotive::Steam::ContentFieldValues do

  describe 'what a refused value reports' do

    { 'text that reads as no number'  => [[:integer, '12x'],           :invalid_number],
      'a number past the bounds'      => [[:integer, 2**63],           :outside_numeric_bounds],
      'text past the bounds'          => [[:integer, '9' * 20],        :outside_numeric_bounds],
      'text past the 19-digit cap'    => [[:integer, '0' * 20],        :outside_numeric_bounds],
      'text no int64 could ever hold' => [[:integer, '9' * 1_000_000], :outside_numeric_bounds],
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

  describe 'reading a query operand in no readable encoding' do

    it 'raises the structured encoding error before any parsing' do
      utc = ActiveSupport::TimeZone['UTC']

      [-> { described_class.number(%(12\xFF), :integer) },
       -> { described_class.boolean(%(tru\xFF)) },
       -> { described_class.date(%(2020-01-01\xFF)) },
       -> { described_class.date_time(%(2020-01-01T10:00\xFF), utc) }].each do |call|
        expect { call.call }.to raise_error(described_class::ParseError) do |error|
          expect(error.reason).to eq :invalid_encoding
        end
      end
    end

  end

  describe '#normalize_read' do

    { 'an integer'    => [:integer, '7',          7],
      'a boolean'     => [:boolean, 'true',       true],
      'a date'        => [:date,    '2024-01-20', Date.new(2024, 1, 20)],
      'a JSON object' => [:json,    '{"a":1}',    { 'a' => 1 }]
    }.each do |label, (type, text, value)|
      it "reads text into #{label} on the way in and refuses it on the way out" do
        expect(described_class.normalize_input(type, text)).to eq value

        expect { described_class.normalize_read(type, text) }
          .to raise_error(described_class::ParseError) { |error| expect(error.reason).to eq :wrong_stored_type }

        expect(described_class.normalize_read(type, value)).to eq value
      end
    end

    { 'a moment where a day goes'    => [:date,      Time.utc(2013, 2, 11, 22), Date.new(2013, 2, 11)],
      'a day already read'           => [:date,      Date.new(2013, 2, 11),     Date.new(2013, 2, 11)],
      'a moment carrying an offset'  => [:date_time, Time.new(2012, 6, 6, 14, 0, 0, '+02:00'), Time.utc(2012, 6, 6, 12)],
      'a day where a moment goes'    => [:date_time, Date.new(2013, 2, 11),     Date.new(2013, 2, 11)],
      'a day spelled out'            => [:date,      '2013-02-11',              '2013-02-11'],
      'a moment spelled out'         => [:date_time, '2012-06-06T12:00:00Z',    '2012-06-06T12:00:00Z'],
      'a type no store writes'       => [:date,      :whenever,                 :whenever]
    }.each do |label, (type, stored, expected)|
      it "deserializes #{label}" do
        expect(described_class.deserialize(type, stored)).to eql expected
      end
    end

    describe 'what a store may hold' do

      { 'an integer'    => [:integer, 7,                     7],
        'a float'       => [:float,   1.5,                   1.5],
        'true'          => [:boolean, true,                  true],
        'false'         => [:boolean, false,                 false],
        'text'          => [:string,  'hello',               'hello'],
        'a day'         => [:date,    Date.new(2024, 1, 20), Date.new(2024, 1, 20)],
        'an object'     => [:json,    { 'a' => 1 },          { 'a' => 1 }],
        'nothing'       => [:integer, nil,                   nil],
        'no day'        => [:date,    nil,                   nil]
      }.each do |label, (type, value, expected)|
        it("reads #{label}") { expect(described_class.normalize_read(type, value)).to eq expected }
      end

      it 'reads a moment in UTC, whichever offset it carries' do
        value = Time.new(2024, 1, 20, 12, 0, 0, '+03:00')

        expect(described_class.normalize_read(:date_time, value)).to eq value
        expect(described_class.normalize_read(:date_time, value)).to be_utc
      end

      it 'leaves a type it does not read alone' do
        expect(described_class.normalize_read(:select, 'option')).to eq 'option'
      end

    end

    describe 'what a store holds wrongly' do

      { 'an integer where a float goes'   => [:float,     3],
        'a float where an integer goes'   => [:integer,   3.0],
        'a number where a boolean goes'   => [:boolean,   1],
        'a moment where a day goes'       => [:date,      Time.utc(2024, 1, 20)],
        'a DateTime where a day goes'     => [:date,      DateTime.new(2024, 1, 20)],
        'a day where a moment goes'       => [:date_time, Date.new(2024, 1, 20)],
        'a zoned time where a moment goes' => [:date_time, ActiveSupport::TimeZone['UTC'].parse('2024-01-20')],
        'a number where text goes'        => [:string,    7],
        'a list where an object goes'     => [:json,      [1, 2]]
      }.each do |label, (type, value)|
        it "reports wrong_stored_type for #{label}" do
          expect { described_class.normalize_read(type, value) }
            .to raise_error(described_class::ParseError) { |error| expect(error.reason).to eq :wrong_stored_type }
        end
      end

      { 'a number past the bounds'     => [[:integer, 2**63],           :outside_numeric_bounds],
        'a non-finite float'           => [[:float,   Float::INFINITY], :outside_numeric_bounds],
        'text in no readable encoding' => [[:string,  %(caf\xFF)],      :invalid_encoding],
        'a value JSON cannot hold'     => [[:json,    { 'v' => :sym }], :invalid_json_value],
        'a name JSON cannot use'       => [[:json,    { 1 => 'x' }],    :invalid_json_name]
      }.each do |label, ((type, value), reason)|
        it "reports #{reason} for #{label}" do
          expect { described_class.normalize_read(type, value) }
            .to raise_error(described_class::ParseError) { |error| expect(error.reason).to eq reason }
        end
      end

      it 'reports only the expected and actual types' do
        expect { described_class.normalize_read(:integer, '7') }
          .to raise_error(described_class::ParseError, 'expected an integer, got String')
      end

      it 'refuses a value that only claims to be a boolean' do
        impostor = Object.new
        impostor.define_singleton_method(:==) { |_other| true }

        expect { described_class.normalize_read(:boolean, impostor) }
          .to raise_error(described_class::ParseError) { |error| expect(error.reason).to eq :wrong_stored_type }
      end

      it 'refuses an object that holds itself rather than running out of stack' do
        loop_back = { 'a' => 1 }
        loop_back['self'] = loop_back

        expect { described_class.normalize_read(:json, loop_back) }
          .to raise_error(described_class::ParseError) { |error| expect(error.reason).to eq :json_too_deep }
      end

    end

    describe 'what the store goes on holding' do

      it 'hands back its own copy of an object' do
        stored = { 'a' => [1], 'b' => +'text' }
        read   = described_class.normalize_read(:json, stored)

        read['a'] << 2
        read['b'] << '!'

        expect(stored).to eq('a' => [1], 'b' => 'text')
      end

      it 'hands back its own copy of text' do
        stored = +'hello'

        described_class.normalize_read(:string, stored) << ' there'

        expect(stored).to eq 'hello'
      end

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
