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

  describe '.sizes' do

    {
      ['4096x', 6000, 3000]       => [[4096, 2048]],
      ['x30', 7, 3]               => [[70, 30]],
      ['40x30', 60, 40]           => [[40, 27]],
      ['40x30>', 7, 3]            => [[7, 3]],
      ['40x40>', 30, 50]          => [[24, 40]],
      ['40x40<', 30, 50]          => [[30, 50]],
      ['40x<', 30, 50]            => [[40, 67]],
      ['40x30^', 7, 3]            => [[70, 30]],
      ['40x!', 7, 3]              => [[40, 3]],
      ['150x%', 7, 3]             => [[11, 5]],
      ['50x%', 4000, 5000]        => [[2000, 2500]],
      ['x50%', 60, 40]            => [[60, 20]],
      ['2400@', 60, 40]           => [[60, 40]],
      ['2292x1125#', 1000, 20000] => [[2292, 45840], [2292, 1125]],
      ['1x1#', 60, 40]            => [[2, 1], [1, 1]],
      ['0x0+0+0', 6000, 3000]     => [[6000, 3000]],
      ['500x500+9000+9000', 600, 300] => [[500, 300]],
      ['700x700+0+0', 600, 300]   => [[600, 300]]
    }.each do |(geometry, width, height), sizes|
      it "passes a #{width}x#{height} frame resized to #{geometry} through #{sizes.map { |size| size.join('x') }.join(', ')}" do
        expect(described_class.sizes(geometry, width, height)).to eq sizes
      end
    end

    it 'bounds a zero side above what ImageMagick makes of it' do
      expect(described_class.sizes('0x30', 60, 40)).to eq [[45, 30]]
      expect(described_class.sizes('0x30^', 40, 60)).to eq [[30, 45]]
    end

  end

  describe '.within_bounds?' do

    {
      ['5760x', 9000, 3000]        => true,
      ['5761x', 9000, 3000]        => false,
      ['x5760', 3000, 9000]        => true,
      ['x5761', 3000, 9000]        => false,
      ['5000x5000!', 10, 10]       => true,
      ['5001x5000!', 10, 10]       => false,
      ['5760x>', 9000, 3000]       => true,
      ['5760x<', 9000, 3000]       => false,
      ['2292x1125#', 4032, 3024]   => true,
      ['2292x1125#', 1000, 20000]  => false,
      ['2000x1000#', 6000, 18000]  => true,
      ['1000x2000#', 18000, 6000]  => true,
      ['2000x1000#', 1000, 10000]  => false,
      ['1000x2000#', 10000, 1000]  => false,
      ['2000x1000#', 1000, 6250]   => true,
      ['2000x1000#', 1000, 6251]   => false,
      ['x500>', 20000, 400]        => false,
      ['500x>', 400, 20000]        => false,
      ['200x200%', 5000, 5000]     => false,
      ['100x100>', 5000, 5000]     => true,
      ['0x0+0+0', 6000, 3000]      => false,
      ['500x500+9000+9000', 6000, 3000] => true,
      ['99999x99999+0+0', 600, 300] => true,
      ['25000000@', 5000, 5000]    => true
    }.each do |(geometry, width, height), allowed|
      it "#{allowed ? 'allows' : 'refuses'} #{geometry} for a #{width}x#{height} frame" do
        expect(described_class.within_bounds?(geometry, width, height)).to be allowed
      end
    end

    it 'bounds an output by the side and the area the configuration sets' do
      allow(Locomotive::Steam.configuration).to receive_messages(image_resizer_max_side: 4096, image_resizer_max_area: 16_000_000)

      expect(described_class.within_bounds?('4096x', 6000, 3000)).to be true
      expect(described_class.within_bounds?('4097x', 6000, 3000)).to be false
      expect(described_class.within_bounds?('4000x4000!', 10, 10)).to be true
      expect(described_class.within_bounds?('4001x4000!', 10, 10)).to be false
    end

    it 'bounds a resize before its crop by the output area the configuration sets, not by its side' do
      allow(Locomotive::Steam.configuration).to receive(:image_resizer_max_area).and_return(16_000_000)

      expect(described_class.within_bounds?('2000x1000#', 1000, 4000)).to be true
      expect(described_class.within_bounds?('2000x1000#', 1000, 4001)).to be false
    end

    it 'allows a percentage that keeps both sides within the bounds' do
      expect(described_class.within_bounds?('50x%', 4000, 5000)).to be true
    end

    it 'refuses an area of hundreds of digits without an error' do
      expect(described_class.within_bounds?("#{'9' * 400}@", 60, 40)).to be false
    end

    {
      ['100x100>', [6000, 6000]] => false,
      ['50x50%', [6000, 6000]]   => true,
      ['20x', [3000, 3000]]      => false,
      ['20x20#', [6000, 6000]]   => true,
      ['20x20+0+0', [6000, 6000]] => true
    }.each do |(geometry, canvas), allowed|
      it "#{allowed ? 'allows' : 'refuses'} #{geometry} for a 10x10 frame on a #{canvas.join('x')} canvas" do
        expect(described_class.within_bounds?(geometry, 10, 10, canvas: canvas)).to be allowed
      end
    end

    {
      ['100x100>', 10, 10, { canvas: [5000, 5000] }] => [5000, 5000],
      ['50x50%', 10, 10, { canvas: [5000, 5000] }]   => [2500, 2500],
      ['20x20#', 10, 10, { canvas: [5000, 5000] }]   => [20, 20],
      ['4096x', 6000, 3000, {}]                      => [4096, 2048],
      ['1x1', 10, 10, { canvas: [1, 1], offset: [60000, 60000] }]     => [6001, 6001],
      ['1x1', 10, 10, { canvas: [3, 3], offset: [20000, 0] }]         => [2001, 1],
      ['x2', 11, 10, { canvas: [2, 1], offset: [60000, 0] }]          => [16367, 2],
      ['5x5', 10, 10, { canvas: [1, 1], offset: [60000, 60000] }]     => [30005, 30005],
      ['1x1', 10, 10, { canvas: [1, 1] }]                             => [1, 1],
      ['1x1', 10, 10, { canvas: [10, 10], offset: [-60000, -60000] }] => [1, 1],
      ['100x100>', 10, 10, { canvas: [100, 100], offset: [6000, 6000] }] => [100, 100]
    }.each do |(geometry, width, height, frame), size|
      placed = "#{" on a #{frame[:canvas].join('x')} canvas" if frame[:canvas]}#{" at #{frame[:offset].map { |side| format('%+d', side) }.join}" if frame[:offset]}"

      it "gives #{size.join('x')} as the output of #{geometry} for a #{width}x#{height} frame#{placed}" do
        expect(described_class.output_size(geometry, width, height, **frame)).to eq size
      end
    end

    it 'gives no bound for a canvas narrower than its frame that a negative offset may wrap round' do
      expect(described_class.within_bounds?('1x1', 10, 10, canvas: [1, 1], offset: [-60000, -60000])).to be false
      expect(described_class.within_bounds?('1x1', 10, 10, canvas: [1, 1], offset: [-5, 0])).to be false
    end

    it 'leaves a frame of no size to ImageMagick' do
      expect(described_class.within_bounds?('200x200%', 0, 5000)).to be true
      expect(described_class.within_bounds?('40x30#', 0, 10)).to be true
    end

  end

end
