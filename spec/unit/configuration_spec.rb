require 'spec_helper'

describe Locomotive::Steam::Configuration do

  subject { Locomotive::Steam::Configuration.new }

  describe 'default values' do

    it { expect(subject.mode).to eq(:production) }
    it { expect(subject.serve_assets).to eq(true) }
    it { expect(subject.asset_path).to eq(nil) }

  end

  describe 'the trusted remote resize source prefix' do

    it { expect(subject.image_resizer_remote_source_prefix).to eq nil }

    it 'takes a URL prefix' do
      subject.image_resizer_remote_source_prefix = 'https://cdn.example.com/sites/'
      expect(subject.image_resizer_remote_source_prefix).to eq 'https://cdn.example.com/sites/'
    end

  end

  describe 'assign a different value' do

    before { subject.mode = :test }
    it { expect(subject.mode).to eq(:test) }

    context 'the initial value was true' do

      before { subject.serve_assets = false }
      it { expect(subject.serve_assets).to eq(false) }

    end

  end

end
