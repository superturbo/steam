require 'spec_helper'

describe Locomotive::Steam::Liquid::Drops::SectionBlock do

  let(:section) { instance_double('Section', definition: { 'blocks' => [] }) }
  let(:block) { instance_double('block') }
  let(:index) { 0 }
  let(:drop) { described_class.new(section, block, index) }

  describe '#locomotive_attributes' do

    let(:block)        { { 'id' => %(c"d), 'settings' => {} } }
    let(:section_drop) { Locomotive::Steam::Liquid::Drops::Section.new(section, { 'id' => %(a"b) }) }

    before { drop.context = ::Liquid::Context.new('section' => section_drop) }

    it 'encodes the ids of the section and the block' do
      expect(drop.locomotive_attributes).to eq %(data-locomotive-block="section-a&quot;b-block-c&quot;d")
    end

  end

  describe '#has_leaves?' do

    subject { drop.has_leaves? }

    it { is_expected.to eq false }

    context 'the block has leaves' do

      before { drop.leaves << instance_double('SectionBlock') }

      it { is_expected.to eq true }

    end

  end

end
