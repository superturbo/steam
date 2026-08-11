require 'spec_helper'

require_relative '../../../support/content_entry_repository_context'

describe Locomotive::Steam::ContentEntryRepository do

  include_context 'content entry repository'

  describe '#conditions_without_order_by' do

    let(:conditions) { {} }

    subject { repository.with(type).send(:conditions_without_order_by, conditions) }

    def prepared_for(conditions)
      repository.with(type).send(:conditions_without_order_by, conditions).first
    end

    context 'date fields' do

      let(:value)       { '2009/09/10' }
      let(:field)       { instance_double('DateField', name: 'launched_at', persisted_name: 'launched_at', type: :date) }
      let(:_fields)     { instance_double('Fields', selects: [], belongs_to: [], many_to_many: [], dates_and_date_times: [field], numbers: [], booleans: []) }
      let(:conditions)  { { 'launched_at' => value } }

      it { is_expected.to eq([{ '_visible' => true, 'content_type_id' => 1, 'launched_at' => Date.parse('2009/09/10') }, nil]) }

      # A day names no instant, so nothing asks for the zone.
      context 'without a site' do
        let(:site) { nil }

        it { expect(subject.first['launched_at']).to eql Date.new(2009, 9, 10) }
      end

    end

    context 'date time fields' do

      before { Time.zone = 'Paris' }

      let(:value)       { '2007-06-29T21:15:00' }
      let(:field)       { instance_double('DateField', name: 'launched_at', persisted_name: 'launched_at', type: :date_time) }
      let(:_fields)     { instance_double('Fields', selects: [], belongs_to: [], many_to_many: [], dates_and_date_times: [field], numbers: [], booleans: []) }
      let(:conditions)  { { 'launched_at' => value } }

      # Time.zone belongs to whatever request is running; the site decides.
      it 'reads an offset-less time in the site zone, not the process one' do
        expect(subject.first['launched_at']).to eql Time.utc(2007, 6, 29, 21, 15)
      end

      context 'a to_s string' do
        let(:value) { '2007-06-29 23:15:00 +0200' }

        it 'reads as the instant it names' do
          expect(subject.first['launched_at']).to eql Time.utc(2007, 6, 29, 21, 15)
        end
      end

      context 'a to_s string of a UTC site' do
        let(:value) { '2007-06-29 21:15:00 UTC' }

        it { expect(subject.first['launched_at']).to eql Time.utc(2007, 6, 29, 21, 15) }
      end

      context 'a site behind UTC' do
        let(:site) do
          instance_double('Site', _id: 1, default_locale: :en, locales: %i(en fr),
                          timezone: ActiveSupport::TimeZone['America/New_York'])
        end

        it { expect(subject.first['launched_at']).to eql Time.utc(2007, 6, 30, 1, 15) }

        # A calendar date names a day; the site decides which instant it is.
        context 'given a Date' do
          let(:value) { Date.new(2013, 2, 11) }

          it { expect(subject.first['launched_at']).to eql Time.utc(2013, 2, 11, 5) }
        end
      end

      context 'without a site to read it in' do
        let(:site) { nil }

        it 'says what it is missing' do
          expect { subject }
            .to raise_error(Locomotive::Steam::ContentFieldValues::ConfigurationError, /site timezone is required/)
        end
      end

      context 'with a timezone no zone table knows' do
        let(:site) do
          instance_double('Site', _id: 1, default_locale: :en, locales: %i(en fr),
                          timezone: nil, timezone_name: 'Mars/Olympus')
        end

        it { expect { subject }.to raise_error(Locomotive::Steam::ContentFieldValues::ConfigurationError, /Mars/) }
      end

      it 'keeps the instant an operand spells its own offset for' do
        expect(described_class.new(adapter, site, locale, content_type_repository)
                 .with(type).send(:conditions_without_order_by, 'launched_at' => '2007-06-29T21:15:00Z')
                 .first['launched_at'])
          .to eql Time.utc(2007, 6, 29, 21, 15)
      end

      context 'surrounded by whitespace' do
        let(:value) { "\t2019-09-10T10:30:00Z\n" }

        it { expect(subject.first['launched_at']).to eql Time.utc(2019, 9, 10, 10, 30) }
      end

      # The slash form belongs to a date, and a date and time joins them with T.
      ['2007/06/29', '2007/06/29 21:15:00', '2007-06-29 21:15:00'].each do |rejected|
        context rejected.inspect do
          let(:value) { rejected }
          it { expect(subject.first['launched_at']).to eq Locomotive::Steam::Adapters::Query::Values.unmatchable }
        end
      end

    end

    context 'date fields' do

      before { Time.zone = 'Paris' }

      let(:field)       { instance_double('DateField', name: 'held_on', persisted_name: 'held_on', type: :date) }
      let(:_fields)     { instance_double('Fields', selects: [], belongs_to: [], many_to_many: [], dates_and_date_times: [field], numbers: [], booleans: []) }
      let(:conditions)  { { 'held_on' => value } }

      # The documented with_scope example spells a date with slashes.
      ['2012-01-02', '2012/01/02', ' 2012/01/02 '].each do |written|
        context written.inspect do
          let(:value) { written }
          it { expect(subject.first['held_on']).to eq Date.new(2012, 1, 2) }
        end
      end

      ['tomorrow', '2012-99-99', '2012-01-02 10:00:00', '2012-01-02 10:00:00 +03:00', ''].each do |bad|
        context bad.inspect do
          let(:value) { bad }
          it { expect(subject.first['held_on']).to eq Locomotive::Steam::Adapters::Query::Values.unmatchable }
        end
      end

      # Liquid renders {{ now }} through to_s and the action bridge through
      # as_json; the framework's own output has to work as an operand.
      describe 'a moment spelled as text reads like the Ruby moment' do

        { 'an offset-less ISO time (site zone)' => '2012-01-02T10:00:00',
          'an as_json string'                   => '2012-01-02T23:30:00.123+03:00',
          'a to_s string'                       => '2012-01-02 23:30:00 +0300' }.each do |label, written|
          context label do
            let(:value) { written }
            it { expect(subject.first['held_on']).to eq Date.new(2012, 1, 2) }
          end
        end

        context 'an instant that is still the previous site day' do
          let(:value) { '2012-01-03T00:30:00+01:00' }
          it { expect(subject.first['held_on']).to eq Date.new(2012, 1, 2) }
        end

      end

      context 'a Date operand' do
        let(:value) { Date.new(2012, 1, 2) }
        it { expect(subject.first['held_on']).to eq Date.new(2012, 1, 2) }
      end

      context 'an object that merely answers to_date' do
        let(:value) { double('DateOnly', to_date: Date.new(2012, 1, 2)) }

        it 'is rejected as a date operand' do
          expect { subject }
            .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue, /expected a date/)
        end
      end

      describe 'a moment reads as the day at the site' do

        context 'a zoned moment before the site midnight' do
          let(:value) { Time.utc(2020, 1, 1, 23, 30).in_time_zone('Paris') }
          it { expect(subject.first['held_on']).to eq Date.new(2020, 1, 1) }
        end

        context 'a DateTime before the site midnight' do
          let(:value) { DateTime.new(2020, 1, 2, 0, 30, 0, '+1') }
          it { expect(subject.first['held_on']).to eq Date.new(2020, 1, 1) }
        end

        context 'the site keeps its own day' do
          let(:site) do
            instance_double('Site', _id: 1, default_locale: :en, locales: %i(en fr),
                                    timezone: ActiveSupport::TimeZone['Vilnius'])
          end
          let(:value) { Time.utc(2020, 1, 1, 23, 30) }

          it { expect(subject.first['held_on']).to eq Date.new(2020, 1, 2) }
        end

      end

    end

    context 'boolean fields' do

      let(:field)       { instance_double('BooleanField', name: 'flag', persisted_name: 'flag', type: :boolean) }
      let(:_fields)     { instance_double('Fields', selects: [], belongs_to: [], many_to_many: [], dates_and_date_times: [], numbers: [], booleans: [field]) }
      let(:conditions)  { { 'flag' => value } }

      { true => true, false => false, 'true' => true, ' TRUE ' => true,
        'false' => false, 'False' => false, '1' => true, '0' => false }.each do |written, expected|
        context written.inspect do
          let(:value) { written }
          it { expect(subject.first['flag']).to eq expected }
        end
      end

      # Ruby truthiness is not the grammar: only the listed forms read.
      ['yes', 'on', '', 1, 0, 1.0].each do |bad|
        context bad.inspect do
          let(:value) { bad }

          it do
            if bad.is_a?(String)
              expect(subject.first['flag']).to eq Locomotive::Steam::Adapters::Query::Values.unmatchable
            else
              expect { subject }.to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
            end
          end
        end
      end

      context 'a list operand' do
        let(:conditions) { { 'flag.in' => ['1', 'nope'] } }

        it 'reads every element' do
          expect(subject.first['flag.in']).to eq [true, Locomotive::Steam::Adapters::Query::Values.unmatchable]
        end
      end

    end

    context 'date fields carrying a plain-field expression or a list' do

      let(:field)   { instance_double('DateField', name: 'launched_at', persisted_name: 'launched_at', type: :date) }
      let(:_fields) { instance_double('Fields', selects: [], belongs_to: [], many_to_many: [], dates_and_date_times: [field], numbers: [], booleans: []) }

      it 'leaves a Range untouched' do
        range = Date.new(2012, 1, 1)..Date.new(2012, 12, 31)
        expect(prepared_for('launched_at' => range)).to include('launched_at' => range)
      end

      it 'leaves a Regexp untouched' do
        expect(prepared_for('launched_at' => /2012/)).to include('launched_at' => /2012/)
      end

      it 'converts the elements of a list operand' do
        expect(prepared_for('launched_at.in' => %w(2012-06-29)))
          .to include('launched_at.in' => [Date.new(2012, 6, 29)])
      end

      it 'converts the elements of a Set operand' do
        expect(prepared_for('launched_at.in' => Set['2012-06-29']))
          .to include('launched_at.in' => [Date.new(2012, 6, 29)])
      end

      it 'rejects an unsupported value kind' do
        [true, { 'a' => 1 }].each do |bad|
          expect { prepared_for('launched_at' => bad) }
            .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
        end
      end

      context 'on a date time field' do

        let(:field) { instance_double('DateField', name: 'launched_at', persisted_name: 'launched_at', type: :date_time) }

        it 'rejects a value that cannot convert to a date time' do
          expect { prepared_for('launched_at' => double('DateOnly', to_date: Date.new(2012, 1, 1))) }
            .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
        end

      end

    end

    context 'ISO dash date' do

      let(:value)       { '2019-09-10' }
      let(:field)       { instance_double('DateField', name: 'launched_at', persisted_name: 'launched_at', type: :date) }
      let(:_fields)     { instance_double('Fields', selects: [], belongs_to: [], many_to_many: [], dates_and_date_times: [field], numbers: [], booleans: []) }
      let(:conditions)  { { 'launched_at' => value } }

      it { is_expected.to eq([{ '_visible' => true, 'content_type_id' => 1, 'launched_at' => Date.new(2019, 9, 10) }, nil]) }

    end

    context 'ISO date time with a UTC offset' do

      let(:value)       { '2007-06-29T21:15:00+00:00' }
      let(:field)       { instance_double('DateField', name: 'launched_at', persisted_name: 'launched_at', type: :date_time) }
      let(:_fields)     { instance_double('Fields', selects: [], belongs_to: [], many_to_many: [], dates_and_date_times: [field], numbers: [], booleans: []) }
      let(:conditions)  { { 'launched_at' => value } }

      it { is_expected.to eq([{ '_visible' => true, 'content_type_id' => 1, 'launched_at' => Time.utc(2007, 6, 29, 21, 15) }, nil]) }

    end

    context 'date-only value for a date-time field resolves to midnight' do

      before { Time.zone = 'UTC' }

      let(:value)       { '2019-09-10' }
      let(:field)       { instance_double('DateField', name: 'launched_at', persisted_name: 'launched_at', type: :date_time) }
      let(:_fields)     { instance_double('Fields', selects: [], belongs_to: [], many_to_many: [], dates_and_date_times: [field], numbers: [], booleans: []) }
      let(:conditions)  { { 'launched_at' => value } }

      it { is_expected.to eq([{ '_visible' => true, 'content_type_id' => 1, 'launched_at' => Time.utc(2019, 9, 10) }, nil]) }

    end

    context 'invalid date strings match nothing' do

      let(:field)       { instance_double('DateField', name: 'launched_at', persisted_name: 'launched_at', type: :date_time) }
      let(:_fields)     { instance_double('Fields', selects: [], belongs_to: [], many_to_many: [], dates_and_date_times: [field], numbers: [], booleans: []) }
      let(:conditions)  { { 'launched_at' => value } }

      ['tomorrow', '2025-99-99', ''].each do |bad|
        context bad.inspect do
          let(:value) { bad }
          it { expect(subject.first['launched_at']).to eq Locomotive::Steam::Adapters::Query::Values.unmatchable }
        end
      end

    end

    context 'numeric fields' do

      let(:field_type)  { :float }
      let(:field)       { instance_double('NumberField', name: 'price', persisted_name: 'price', type: field_type) }
      let(:_fields)     { instance_double('Fields', selects: [], belongs_to: [], many_to_many: [], dates_and_date_times: [], numbers: [field], booleans: []) }
      let(:conditions)  { { 'price.lt' => value } }

      def prepared
        subject.first['price.lt']
      end

      def subject_for(conditions)
        repository.with(type).send(:conditions_without_order_by, conditions).first
      end

      context 'a String from params' do
        let(:value) { '42.5' }
        it { expect(prepared).to eq 42.5 }

        context 'on an integer field' do
          let(:field_type) { :integer }
          let(:value)      { '42' }
          it { expect(prepared).to eq 42 }
        end
      end

      context 'a value that is already numeric' do
        let(:value) { 42.5 }
        it { expect(prepared).to eq 42.5 }
      end

      context 'a nil value' do
        let(:value) { nil }
        it { expect(prepared).to be_nil }
      end

      context 'a list operand' do
        let(:conditions) { { 'price.in' => %w(1 2) } }
        it { expect(subject.first['price.in']).to eq [1.0, 2.0] }

        it 'does not mutate the given array' do
          source = %w(1 2)
          repository.with(type).send(:conditions_without_order_by, 'price.in' => source)
          expect(source).to eq %w(1 2)
        end
      end

      context 'a numeric Range' do
        let(:conditions) { { 'price' => (5..6) } }
        it { expect(subject.first['price']).to eq(5..6) }
      end

      context 'a Range bound meets the same rules as a gt or lte operand' do

        def range_for(range)
          subject_for('price' => range)['price']
        end

        it 'reads text bounds as numbers' do
          expect(range_for('10'..'20')).to eq(10.0..20.0)
        end

        it 'keeps an excluded end' do
          expect(range_for('10'...'20')).to eq(10.0...20.0)
        end

        it 'keeps a beginless and an endless side' do
          expect(range_for('10'..)).to eq(10.0..)
          expect(range_for(..'20')).to eq(..20.0)
        end

        it 'matches nothing when a text bound reads as no number' do
          expect(range_for('abc'..'20'))
            .to eq Locomotive::Steam::Adapters::Query::Values.unmatchable
        end

        context 'on an integer field' do
          let(:field_type) { :integer }

          it 'reads integer text bounds' do
            expect(range_for('1'..'5')).to eq(1..5)
          end
        end

        it 'rejects bounds outside the numeric field domain' do
          [Rational(1, 2)..Rational(3, 2),
           BigDecimal('1')..BigDecimal('2'),
           (2**63)..,
           [1]..[2]].each do |bad|
            expect { subject_for('price' => bad) }
              .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
          end
        end

      end

      context 'two conditions bounding the same field' do
        let(:conditions) { { 'price.gte' => '5', 'price.lte' => '10' } }
        it 'converts both, not only the last one' do
          expect(subject.first).to include('price.gte' => 5.0, 'price.lte' => 10.0)
        end
      end

      context 'operators that carry no field value' do
        it 'leaves the exists operand to the operator registry' do
          expect(subject_for('price.exists' => true)).to include('price.exists' => true)
        end

        it 'leaves the size operand to the operator registry' do
          expect(subject_for('price.size' => '2')).to include('price.size' => '2')
        end
      end

      context 'a String no number can equal — a visitor typed it' do
        %w(abc 4.2.1).each do |bad|
          context bad.inspect do
            let(:value) { bad }
            it('matches nothing, and is never turned into nil') { expect(prepared).to eq Locomotive::Steam::Adapters::Query::Values.unmatchable }
          end
        end

        context 'a fractional string on an integer field' do
          let(:field_type) { :integer }
          let(:value)      { '4.2' }
          it { expect(prepared).to eq Locomotive::Steam::Adapters::Query::Values.unmatchable }
        end

        it 'reads only what is numeric inside a list' do
          expect(subject_for('price.in' => ['1', 'abc'])).to include('price.in' => [1.0, Locomotive::Steam::Adapters::Query::Values.unmatchable])
        end

        it 'does not confuse it with a real nil, which means missing or null' do
          expect(subject_for('price.in' => [nil, '1'])).to include('price.in' => [nil, 1.0])
          expect(subject_for('price' => 'abc')).to include('price' => Locomotive::Steam::Adapters::Query::Values.unmatchable)
        end
      end

      context 'the decimal grammar a numeric string has to meet' do

        it 'reads a number through surrounding whitespace' do
          expect(subject_for('price.lt' => ' 10 ')).to include('price.lt' => 10.0)
          expect(subject_for('price.lt' => "\t-10\n")).to include('price.lt' => -10.0)
        end

        it 'reads the sign, fraction and exponent it allows' do
          expect(subject_for('price.lt' => '+1.5e2')).to include('price.lt' => 150.0)
          expect(subject_for('price.lt' => '-.5')).to include('price.lt' => -0.5)
        end

        # Ruby 3.3 rejects a trailing dot where 3.4 reads 5.0, so the grammar
        # cannot accept it without meaning different things on each.
        ['1_5', '0x1', '1 0', '1e9999', '5.', '  ', ''].each do |bad|
          it "matches nothing for #{bad.inspect}" do
            expect(subject_for('price.lt' => bad)).to include('price.lt' => Locomotive::Steam::Adapters::Query::Values.unmatchable)
          end
        end

        context 'on an integer field' do
          let(:field_type) { :integer }

          it 'reads a plain decimal' do
            expect(subject_for('price.lt' => ' +42 ')).to include('price.lt' => 42)
          end

          ['1_5', '4.2', '0x1'].each do |bad|
            it "matches nothing for #{bad.inspect}" do
              expect(subject_for('price.lt' => bad)).to include('price.lt' => Locomotive::Steam::Adapters::Query::Values.unmatchable)
            end
          end

          it 'matches nothing for an out of range integer' do
            [2**63, -2**63 - 1].map(&:to_s).each do |beyond|
              expect(subject_for('price.lt' => beyond)).to include('price.lt' => Locomotive::Steam::Adapters::Query::Values.unmatchable)
            end
          end
        end

      end

      context 'a typed number outside the supported domain' do

        it 'rejects an integer beyond either end of int64' do
          [2**63, -2**63 - 1].each do |bad|
            expect { subject_for('price.lt' => bad) }
              .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
          end
        end

        it 'accepts an integer at either end of int64' do
          [2**63 - 1, -2**63].each do |edge|
            expect(subject_for('price.lt' => edge)).to include('price.lt' => edge)
          end
        end

        it 'rejects a float that is not finite' do
          [Float::INFINITY, -Float::INFINITY, Float::NAN].each do |bad|
            expect { subject_for('price.lt' => bad) }
              .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
          end
        end

        it 'rejects numeric types outside the field domain' do
          [Rational(3, 2), BigDecimal('1.5')].each do |bad|
            expect { subject_for('price.lt' => bad) }
              .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
          end
        end

      end

      context 'an unsupported value kind' do
        it 'raises' do
          [{ 'a' => 1 }, true].each do |bad|
            expect { subject_for('price.lt' => bad) }
              .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
          end
        end
      end

      context 'a key outside the closed grammar' do
        it 'is rejected rather than silently truncated' do
          expect { subject_for('price.gt.extra' => 5) }
            .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
        end
      end

    end

  end

end
