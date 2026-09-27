require 'spec_helper'

describe Locomotive::Steam::Initializers::Dragonfly do

  let(:initializer) { Locomotive::Steam::Initializers::Dragonfly.new }

  subject { ::Dragonfly.app(:steam).plugins[:imagemagick] }

  describe 'with ImagickMagick' do

    before { initializer.run }
    it { is_expected.not_to eq nil }

  end

  describe 'missing ImagickMagick' do

    before do
      ::Dragonfly::App.destroy_apps
      expect(File).to receive(:exist?).and_return(false)
      initializer.run
    end
    it { is_expected.to eq nil }

    after(:all) do
      Locomotive::Steam::Initializers::Dragonfly.new.run
    end

  end

  describe 'the key resize URLs are signed with' do

    let(:configuration) { Locomotive::Steam.configuration }
    let(:mode)          { :production }
    let(:key)           { nil }

    subject { initializer.run; ::Dragonfly.app(:steam).secret }

    # The Dragonfly key is global: restore the suite's key once the stubs are gone.
    around do |example|
      example.run
      initializer.run
    end

    before { allow(configuration).to receive_messages(mode: mode, image_resizer_secret: key) }

    context 'a configured key' do

      let(:key) { 'a deployment key' }
      it { is_expected.to eq 'a deployment key' }

    end

    [nil, '', '  ', 'please change it'].each do |value|

      context "#{value.inspect} outside test mode" do

        let(:key) { value }

        it 'refuses to start' do
          expect { initializer.run }.to raise_error(ArgumentError, /image_resizer_secret/)
        end

      end

    end

    [1, :a_key].each do |value|

      [:production, :test].each do |mode_name|

        context "#{value.inspect} in #{mode_name} mode" do

          let(:mode) { mode_name }
          let(:key)  { value }

          it 'refuses to start' do
            expect { initializer.run }.to raise_error(ArgumentError, /image_resizer_secret/)
          end

        end

      end

    end

    context 'no key in test mode' do

      let(:mode) { :test }

      it 'signs with a key generated at initialization' do
        is_expected.to match(/\A\h{64}\z/)
        expect { initializer.run }.to change { ::Dragonfly.app(:steam).secret }
      end

    end

    context 'the public placeholder in test mode' do

      let(:mode) { :test }
      let(:key)  { 'please change it' }

      it { is_expected.to match(/\A\h{64}\z/) }

    end

    context 'a configured key in test mode' do

      let(:mode) { :test }
      let(:key)  { 'a deployment key' }

      it { is_expected.to eq 'a deployment key' }

    end

  end

end
