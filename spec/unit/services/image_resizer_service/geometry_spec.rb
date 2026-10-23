require 'spec_helper'

describe Locomotive::Steam::ImageResizerService::Geometry do

  %w(40x30 40x30> 50x50% x% x! 100x30! 1200@ 40x30# 40x30#se 20x20+5+5 20x20nw).each do |geometry|
    it "accepts #{geometry}" do
      expect(described_class.allowed?(geometry)).to be true
    end
  end

  {
    'an area of zero'                  => %w(0@ 00@),
    'a zero side to set exactly'       => %w(0x30! 40x0! 0x0! 0x! x0! 00x30!),
    'a zero side to set in percent'    => %w(0x0% 0x50% 50x0% 0x% x0%),
    'an unknown gravity to fill'       => %w(40x30#xx 40x30#q),
    'a crop offset with a gravity'     => %w(20x20+5+5nw 20x20+5c),
    'no geometry form'                 => ['50%', 'abc', '40x30 ', ' 40x30', '40x30#n e', '']
  }.each do |reason, geometries|
    geometries.each do |geometry|
      it "refuses #{geometry.inspect}, #{reason}" do
        expect(described_class.allowed?(geometry)).to be false
      end
    end
  end

  [nil, 300, ['40x30'], { '40x30' => true }].each do |geometry|
    it "refuses #{geometry.inspect}, which is no text" do
      expect(described_class.allowed?(geometry)).to be false
    end
  end

  it 'refuses the job of a geometry it does not accept' do
    expect { described_class.check!('40x30#xx') }
      .to raise_error(Locomotive::Steam::ImageResizerService::Shell::RefusedJob, 'Steam does not run this geometry')
  end

  it 'lets the job of a geometry it accepts run' do
    expect { described_class.check!('40x30#') }.not_to raise_error
  end

end
