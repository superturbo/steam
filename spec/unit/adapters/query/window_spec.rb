require 'spec_helper'

require_relative '../../../../lib/locomotive/steam/adapters/query'

describe Locomotive::Steam::Adapters::Query::Window do

  describe '.normalize' do

    subject { described_class.normalize(value, :limit) }

    context 'nothing was asked for' do
      let(:value) { nil }
      it { is_expected.to be_nil }
    end

    context 'a whole number of documents' do
      [0, 1, 250].each do |given|
        context given.inspect do
          let(:value) { given }
          it { is_expected.to eq given }
        end
      end
    end

    context 'a negative number' do
      let(:value) { -1 }
      it { expect { subject }.to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue) }
    end

    context 'a value outside the supported range' do
      let(:value) { 2**63 }
      it { expect { subject }.to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue) }
    end

    context 'the largest supported value' do
      let(:value) { 2**63 - 1 }
      it { is_expected.to eq 2**63 - 1 }
    end

    context 'a value that is not a whole number' do
      ['2', 1.5, true, [2]].each do |given|
        context given.inspect do
          let(:value) { given }
          it { expect { subject }.to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue) }
        end
      end
    end

    it 'names the one it was given' do
      expect { described_class.normalize(-1, :offset) }
        .to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue, /offset/)
    end

  end

end
