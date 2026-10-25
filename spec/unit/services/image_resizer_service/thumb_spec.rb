require 'spec_helper'
require 'open3'

describe Locomotive::Steam::ImageResizerService::Thumb do

  let(:app)       { ::Dragonfly.app(:steam) }
  let(:content)   { ::Dragonfly::Content.new(app, 'image') }
  let(:processor) { described_class.new }
  let(:decode)    { { 'decode' => 'jpeg-1x-v1' } }

  # As identify reports a frame: its canvas is its own size, at no offset, unless one is given.
  def source(format, *frames, orientation: 'Undefined')
    frames = frames.map do |width, height, canvas_width = width, canvas_height = height, x = 0, y = 0, turn = orientation|
      { 'size' => [width, height], 'canvas' => [canvas_width, canvas_height], 'offset' => [x, y], 'orientation' => turn }
    end
    allow(content).to receive(:analyse).with(:steam_image).and_return('format' => format, 'frames' => frames)
  end

  describe 'a job with the orient option' do

    let(:refused) { [Locomotive::Steam::ImageResizerService::Shell::RefusedJob, 'Steam does not resize to this size'] }
    let(:calls)   { [] }

    before { allow(::Dragonfly::ImageMagick::Commands).to receive(:convert) { |_, *args| calls << args } }

    def frame(width, height, canvas: [width, height], offset: [0, 0], orientation: 'TopLeft', was: nil)
      { 'size' => [width, height], 'canvas' => canvas, 'offset' => offset, 'orientation' => orientation, 'source_orientation' => was }
    end

    # As identify pings the source, then the frames as ImageMagick orients them, each with the orientation it had.
    def oriented(format, source, frames)
      allow(content).to receive(:analyse).with(:steam_image).and_return('format' => format, 'frames' => source)
      allow(Locomotive::Steam::ImageResizerService::SourceImage).to receive(:oriented).and_return('format' => format, 'frames' => frames)
    end

    def measured
      Locomotive::Steam::ImageResizerService::SourceImage
    end

    it 'measures the image as ImageMagick orients it, then orients and resizes it in one command' do
      oriented('jpeg', [frame(1800, 1200, orientation: 'RightTop')], [frame(1200, 1800, was: 'RightTop')])

      processor.call(content, '900x>', 'orient' => true)

      expect(measured).to have_received(:oriented).with(content, nil, nil)
      expect(calls).to eq [['-auto-orient +repage -resize 900x>', { 'format' => nil, 'frame' => nil, 'input_args' => nil }]]
    end

    it 'measures and resizes the frame a job names, in the format the job writes' do
      oriented('gif', [frame(10, 10), frame(10, 20, orientation: 'RightTop')], [frame(20, 10, was: 'RightTop')])

      processor.call(content, '900x>', 'orient' => true, 'frame' => 1, 'format' => 'png')

      expect(measured).to have_received(:oriented).with(content, 1, nil)
      expect(calls).to eq [['-auto-orient +repage -resize 900x>', { 'format' => 'png', 'frame' => 1, 'input_args' => nil }]]
    end

    {
      'TopLeft' => '900x600', 'TopRight' => '900x600', 'BottomRight' => '900x600', 'BottomLeft' => '900x600',
      'LeftTop' => '1350x900', 'RightTop' => '1350x900', 'RightBottom' => '1350x900', 'LeftBottom' => '1350x900'
    }.each do |orientation, size|
      it "asks for #{size} to decode a #{orientation} JPEG in its encoded orientation, for the ratio the oriented image needs" do
        oriented('jpeg', [frame(1800, 1200, orientation: orientation)], [frame(900, 600, was: orientation)])

        processor.call(content, '900x>', decode.merge('orient' => true))

        expect(measured).to have_received(:oriented).with(content, nil, "-define jpeg:size=#{size}")
        expect(calls.last.last).to include('input_args' => "-define jpeg:size=#{size}")
      end
    end

    %w(Undefined TopLeft).each do |orientation|
      it "keeps the canvas of an image ImageMagick left #{orientation}" do
        oriented('gif', [frame(10, 10, canvas: [100, 100], offset: [5, 5], orientation: orientation)],
                 [frame(10, 10, canvas: [100, 100], offset: [5, 5], was: orientation)])

        processor.call(content, '900x>', 'orient' => true)

        expect(calls.last.first).to eq '-auto-orient -resize 900x>'
      end
    end

    it 'keeps the canvas of every frame of a sequence, one turned among them' do
      oriented('miff', [frame(10, 20, orientation: 'RightTop'), frame(10, 10, canvas: [100, 10], offset: [80, 0])],
               [frame(20, 10, canvas: [20, 100], was: 'RightTop'), frame(10, 10, canvas: [100, 10], offset: [80, 0], was: 'TopLeft')])

      processor.call(content, '900x>', 'orient' => true)

      expect(calls.last.first).to eq '-auto-orient -resize 900x>'
    end

    it 'bounds the image as ImageMagick orients it, before anything is resized' do
      oriented('jpeg', [frame(9000, 3000, orientation: 'RightTop')], [frame(3000, 9000, was: 'RightTop')])

      expect { processor.call(content, '5760x', 'orient' => true) }.to raise_error(*refused)
      expect(calls).to be_empty
    end

    it 'bounds a single image it repages on a canvas of its own size' do
      oriented('miff', [frame(10, 10, orientation: 'RightBottom')], [frame(10, 10, canvas: [6000, 6000], offset: [10, 0], was: 'RightBottom')])

      expect { processor.call(content, '100x100>', 'orient' => true, 'format' => 'mng') }.not_to raise_error
    end

    it 'bounds a sequence on the canvas ImageMagick leaves it' do
      oriented('miff', [frame(10, 10, orientation: 'RightBottom'), frame(10, 10)],
               [frame(10, 10, canvas: [6000, 6000], offset: [10, 0], was: 'RightBottom'), frame(10, 10, was: 'TopLeft')])

      expect { processor.call(content, '100x100>', 'orient' => true, 'format' => 'mng') }.to raise_error(*refused)
    end

    ['yes', false, 1].each do |value|
      it "refuses an orient option of #{value.inspect} before anything runs" do
        expect(content).not_to receive(:analyse)

        expect { processor.call(content, '900x>', 'orient' => value) }
          .to raise_error(Locomotive::Steam::ImageResizerService::Shell::RefusedJob, 'Steam does not run this orient option')
      end
    end

  end

  describe 'a job without the decode option' do

    it 'reads the image, then is processed as Dragonfly processes it' do
      source('png', [1000, 800], [1000, 800])
      expect(::Dragonfly::ImageMagick::Commands).to receive(:convert)
        .with(content, processor.args_for_geometry('900x>'), { 'format' => 'webp', 'frame' => 1 })

      processor.call(content, '900x>', 'format' => 'webp', 'frame' => 1)
    end

  end

  describe 'a job whose output or intermediate image Steam does not run' do

    let(:refused) { [Locomotive::Steam::ImageResizerService::Shell::RefusedJob, 'Steam does not resize to this size'] }

    before { allow(::Dragonfly::ImageMagick::Commands).to receive(:convert) }

    [{}, { 'decode' => 'jpeg-1x-v1' }].each do |opts|
      context(opts.empty? ? 'without the decode option' : 'with the decode option') do

        it 'runs a side of 5760 and refuses one of 5761' do
          source('jpeg', [9000, 3000])

          expect { processor.call(content, '5760x', opts) }.not_to raise_error
          expect { processor.call(content, '5761x', opts) }.to raise_error(*refused)
        end

        it 'refuses an image filled past the bounds before it is cropped' do
          source('jpeg', [1000, 20000])

          expect { processor.call(content, '2292x1125#', opts) }.to raise_error(*refused)
          expect(::Dragonfly::ImageMagick::Commands).not_to have_received(:convert)
        end

      end
    end

    it 'bounds a JPEG at each size it may decode to, not at its full size alone' do
      source('jpeg', [16832, 12682])

      expect { processor.call(content, '5760x') }.not_to raise_error
      expect { processor.call(content, '5760x', decode) }.to raise_error(*refused)
    end

    it 'bounds a JPEG at a decoded size equal to the size it asks for' do
      source('jpeg', [15808, 11910])

      expect { processor.call(content, '5760x') }.not_to raise_error
      expect { processor.call(content, '5760x', decode) }.to raise_error(*refused)
    end

    it 'bounds a JPEG decoded smaller by the canvas it decodes to, for an output that keeps one' do
      source('jpeg', [11520, 100])

      expect { processor.call(content, '5760x', decode.merge('format' => 'gif')) }.not_to raise_error
    end

    it 'refuses an area of hundreds of digits, and a fill of as many, before conversion' do
      source('jpeg', [6000, 3000])

      expect { processor.call(content, "#{'9' * 400}@", decode) }.to raise_error(*refused)
      expect { processor.call(content, "#{'9' * 400}x30^", decode) }.to raise_error(*refused)
      expect(::Dragonfly::ImageMagick::Commands).not_to have_received(:convert)
    end

    it 'refuses, before conversion, a size whose decode ratio is finite only until it is scaled' do
      source('jpeg', [1, 1])

      expect { processor.call(content, "#{'9' * 308}x", decode) }.to raise_error(*refused)
      expect(::Dragonfly::ImageMagick::Commands).not_to have_received(:convert)
    end

    it 'bounds the canvas a frame is resized with when the output keeps it' do
      source('gif', [10, 10, 6000, 6000])

      expect { processor.call(content, '100x100>') }.to raise_error(*refused)
      expect { processor.call(content, '20x20#') }.not_to raise_error
    end

    %w(gif87 mng miff unheard).each do |format|
      it "bounds the canvas of #{format} output, as of any format not known to leave it out" do
        source('gif', [10, 10, 6000, 6000])

        expect { processor.call(content, '100x100>', 'format' => format) }.to raise_error(*refused)
      end
    end

    %w(jpg jpeg png png8 png32 tif tiff bmp avif psd ico).each do |format|
      it "leaves the canvas out of #{format} output, which drops it or keeps it as metadata alone" do
        source('gif', [10, 10, 6000, 6000])

        expect { processor.call(content, '100x100>', 'format' => format) }.not_to raise_error
      end
    end

    it 'leaves the canvas out of a PNG source written as itself' do
      source('png', [10, 10, 6000, 6000])

      expect { processor.call(content, '100x100>') }.not_to raise_error
    end

    it 'bounds the canvas of an animated WebP, not of a single WebP frame' do
      source('webp', [10, 10, 6000, 6000], [40, 40, 6000, 6000])

      expect { processor.call(content, '100x100>') }.to raise_error(*refused)
      expect { processor.call(content, '100x100>', 'frame' => 0) }.not_to raise_error
    end

    it 'bounds the canvas an encoder shares across frames, as wide and as tall as any of them' do
      source('tiff', [5001, 1], [1, 5001])

      expect { processor.call(content, '5001x5001+0+0', 'format' => 'mng') }.to raise_error(*refused)
      expect { processor.call(content, '5001x5001+0+0', 'format' => 'gif') }.to raise_error(*refused)
      expect { processor.call(content, '5001x5001+0+0', 'format' => 'tiff') }.not_to raise_error

      source('tiff', [5000, 1], [1, 5000])
      expect { processor.call(content, '5000x5000+0+0', 'format' => 'gif') }.not_to raise_error
    end

    it 'bounds the canvas of each MIFF frame, which keeps one apiece rather than sharing one' do
      source('tiff', [5001, 1], [1, 5001])
      expect { processor.call(content, '5001x5001+0+0', 'format' => 'miff') }.not_to raise_error

      source('gif', [10, 10, 6000, 6000])
      expect { processor.call(content, '100x100>', 'format' => 'miff') }.to raise_error(*refused)
    end

    {
      ['1x1', [10, 10, 1, 1, 60000, 60000]]   => 'a square',
      ['x2', [11, 10, 2, 1, 60000, 0]]        => 'an oblong',
      ['1x1', [10, 10, 1, 1, -60000, -60000]] => 'a negatively placed'
    }.each do |(geometry, frame), shape|
      it "bounds #{shape} frame on a canvas narrower than itself by its offset, for an encoder that sizes a canvas from it" do
        source('miff', frame)

        expect { processor.call(content, geometry, 'format' => 'mng') }.to raise_error(*refused)
        expect { processor.call(content, geometry, 'format' => 'miff') }.not_to raise_error
      end
    end

    it 'bounds the canvas an encoder builds for a sequence by every offset, once any frame canvas may round down to nothing' do
      source('miff', [10, 10, 1, 1, 0, 0], [10, 10, 10, 10, 60000, 60000])

      expect { processor.call(content, '1x1', 'format' => 'mng') }.to raise_error(*refused)
      expect { processor.call(content, '1x1', 'format' => 'miff') }.not_to raise_error
      expect { processor.call(content, '1x1', 'format' => 'mng', 'frame' => 1) }.not_to raise_error
    end

    it 'bounds every frame, not the first alone' do
      source('gif', [10, 10], [5000, 5000])

      expect { processor.call(content, '100x100>') }.not_to raise_error
      expect { processor.call(content, '200x200%') }.to raise_error(*refused)
    end

    it 'bounds only the frame a job names' do
      source('gif', [10, 10], [5000, 5000])

      expect { processor.call(content, '200x200%', 'frame' => 0) }.not_to raise_error
      expect { processor.call(content, '200x200%', 'frame' => 1) }.to raise_error(*refused)
    end

    [{}, { 'decode' => 'jpeg-1x-v1' }].each do |opts|
      it "bounds the only frame of a source a frame index past it names, #{opts.empty? ? 'without' : 'with'} the decode option" do
        source('jpeg', [600, 300])

        expect { processor.call(content, '5760x', opts.merge('frame' => 1)) }.not_to raise_error
        expect { processor.call(content, '5761x', opts.merge('frame' => 1)) }.to raise_error(*refused)
      end
    end

    ['1.2', '1.0', 1.0, -1, '-1', 'x', ''].each do |frame|
      it "refuses a frame option of #{frame.inspect}, which is no whole frame index" do
        expect(content).not_to receive(:analyse)

        expect { processor.call(content, '40x30', 'frame' => frame) }
          .to raise_error(Locomotive::Steam::ImageResizerService::Shell::RefusedJob, 'Steam does not run this frame option')
        expect(::Dragonfly::ImageMagick::Commands).not_to have_received(:convert)
      end
    end

    [{}, { 'decode' => 'jpeg-1x-v1' }].each do |opts|
      it "refuses a frame index past what ImageMagick reads exactly, #{opts.empty? ? 'without' : 'with'} the decode option" do
        source('jpeg', [600, 300])

        ['9' * 30, 10**30, 2**53 + 1, (2**53 + 1).to_s].each do |frame|
          expect { processor.call(content, '40x30', opts.merge('frame' => frame)) }
            .to raise_error(Locomotive::Steam::ImageResizerService::Shell::RefusedJob, 'Steam does not run this frame option')
        end
        expect { processor.call(content, '40x30', opts.merge('frame' => (2**53).to_s)) }.not_to raise_error
      end

      it "hands ImageMagick the frame index it bounds, #{opts.empty? ? 'without' : 'with'} the decode option" do
        source('jpeg', [600, 300], [600, 300])

        processor.call(content, '40x30', opts.merge('frame' => '1'))

        expect(::Dragonfly::ImageMagick::Commands).to have_received(:convert).with(content, anything, hash_including('frame' => 1))
      end
    end

    it 'refuses an image with no frame to bound' do
      source('png')

      expect { processor.call(content, '40x30') }.to raise_error(*refused)
    end

  end

  describe 'a job reading a sequence of frames' do

    let(:refused) { [Locomotive::Steam::ImageResizerService::Shell::RefusedJob, 'Steam does not resize a sequence this large'] }

    before { allow(::Dragonfly::ImageMagick::Commands).to receive(:convert) }

    def bound(area)
      allow(Locomotive::Steam.configuration).to receive(:image_resizer_max_area).and_return(area)
    end

    it 'refuses frames whose outputs together pass the sequence area, though each fits, running nothing' do
      source('gif', *[[600, 600]] * 15)

      expect { processor.call(content, '2292x1125#') }.to raise_error(*refused)
      expect(::Dragonfly::ImageMagick::Commands).not_to have_received(:convert)
    end

    it 'runs a sequence whose outputs make the sequence area, and refuses one a pixel past it' do
      source('gif', [100, 50], [100, 50])

      bound(10_000)
      expect { processor.call(content, '100x50') }.not_to raise_error
      bound(9_999)
      expect { processor.call(content, '100x50') }.to raise_error(*refused)
    end

    it 'bounds the resize a fill makes before its crop apart from its output, adding neither to the other' do
      source('gif', [1000, 100], [1000, 100])

      bound(200_000)
      expect { processor.call(content, '100x100#') }.not_to raise_error
      bound(199_999)
      expect { processor.call(content, '100x100#') }.to raise_error(*refused)
    end

    it "counts the sizes a JPEG may decode to as the choices they are, the largest output for each frame" do
      source('jpeg', [999, 500], [999, 500])

      bound(10_200)
      expect { processor.call(content, '100x100', decode) }.not_to raise_error
      bound(10_199)
      expect { processor.call(content, '100x100', decode) }.to raise_error(*refused)
    end

    it 'counts the largest fill a JPEG may decode to before its crop, for each frame' do
      source('jpeg', [1000, 333], [1000, 333])

      bound(60_200)
      expect { processor.call(content, '100x100#', decode) }.not_to raise_error
      bound(60_199)
      expect { processor.call(content, '100x100#', decode) }.to raise_error(*refused)
    end

    it 'takes one JPEG and the sizes it may decode to for no sequence' do
      source('jpeg', [800, 800])
      bound(10_000)

      expect { processor.call(content, '100x100', decode) }.not_to raise_error
    end

    it 'leaves the canvas an encoder shares across the frames out of their sum' do
      source('gif', [100, 100], [100, 100])
      bound(20_000)

      expect { processor.call(content, '100x100') }.not_to raise_error
    end

    it "counts an optimised GIF's frame rectangles, not the canvas each sits on, for an encoder that writes them" do
      source('gif', [1000, 1000], *[[10, 10, 1000, 1000, 500, 500]] * 9)

      bound(1_000_900)
      expect { processor.call(content, '1000x1000>') }.not_to raise_error
      bound(1_000_899)
      expect { processor.call(content, '1000x1000>') }.to raise_error(*refused)
    end

    it 'counts each frame at its canvas for an encoder that may fill frames out to it' do
      source('gif', [1000, 1000], *[[10, 10, 1000, 1000, 500, 500]] * 9)

      bound(10_000_000)
      expect { processor.call(content, '1000x1000>', 'format' => 'webp') }.not_to raise_error
      bound(9_999_999)
      expect { processor.call(content, '1000x1000>', 'format' => 'webp') }.to raise_error(*refused)
    end

    it 'counts every frame at the canvas the frames share for such an encoder, not at its own' do
      source('tiff', [1000, 1000], *[[10, 10]] * 9)
      bound(5_000_000)

      expect { processor.call(content, '1000x1000>') }.not_to raise_error
      expect { processor.call(content, '1000x1000>', 'format' => 'webp') }.to raise_error(*refused)
      expect { processor.call(content, '1000x1000>', 'format' => 'mng') }.to raise_error(*refused)
      bound(10_000_000)
      expect { processor.call(content, '1000x1000>', 'format' => 'webp') }.not_to raise_error
    end

    it 'bounds only the frame a job names' do
      source('gif', *[[600, 600]] * 15)

      expect { processor.call(content, '2292x1125#', 'frame' => 3) }.not_to raise_error
    end

    it 'bounds the pages of a TIFF as a sequence' do
      source('tiff', *[[2000, 2000]] * 8)

      expect { processor.call(content, '2000x') }.to raise_error(*refused)
    end

    it 'bounds the frames as ImageMagick orients them' do
      source('gif', [600, 600])
      oriented = Array.new(15) { { 'size' => [600, 600], 'canvas' => [600, 600], 'offset' => [0, 0], 'orientation' => 'TopLeft' } }
      allow(Locomotive::Steam::ImageResizerService::SourceImage).to receive(:oriented).and_return('format' => 'gif', 'frames' => oriented)

      expect { processor.call(content, '2292x1125#', 'orient' => true) }.to raise_error(*refused)
    end

  end

  describe 'a job with an unknown decode option' do

    it 'is refused before anything runs' do
      expect(::Dragonfly::ImageMagick::Commands).not_to receive(:convert)

      expect { processor.call(content, '900x>', 'decode' => 'jpeg-2x') }
        .to raise_error(Locomotive::Steam::ImageResizerService::Shell::RefusedJob, 'Steam does not run this decode option')
    end

  end

  describe 'a job with a geometry Steam does not run' do

    [{}, { 'decode' => 'jpeg-1x-v1' }].each do |opts|
      it "is refused before anything runs, #{opts.empty? ? 'without' : 'with'} the decode option" do
        expect(content).not_to receive(:analyse)
        expect(::Dragonfly::ImageMagick::Commands).not_to receive(:convert)

        expect { processor.call(content, '40x30#xx', opts) }
          .to raise_error(Locomotive::Steam::ImageResizerService::Shell::RefusedJob, 'Steam does not run this geometry')
      end
    end

  end

  describe 'the JPEG decoding size of a job with the decode option' do

    def input_args(geometry, width, height, format = 'jpeg', orientation: 'Undefined')
      source(format, [width, height], orientation: orientation)
      args = nil
      allow(::Dragonfly::ImageMagick::Commands).to receive(:convert) { |*, opts| args = opts['input_args'] }
      processor.call(content, geometry, decode)
      args
    end

    {
      ['900x>', 4000, 3000]           => '1000x750',  # 0.225 → 2/8
      ['300x200', 4000, 3000]         => '500x375',   # fits: the smaller ratio, 0.067 → 1/8
      ['300x200', 4000, 1000]         => '500x125',   # fits a wide source: 0.075, not 0.2 → 1/8
      ['300x200^', 4000, 3000]        => '500x375',   # fills: the larger ratio, 0.075 → 1/8
      ['750x500#', 5315, 12697]       => '1328x3174', # 0.141 → 2/8
      ['2292x1125#ne', 5315, 12697]   => '2657x6348', # 0.431 → 4/8, odd sides rounded down
      ['900x', 4000, 3000]            => '1000x750',
      ['x323>', 4000, 3000]           => '500x375'    # 0.108 → 1/8
    }.each do |(geometry, width, height), size|
      it "asks for #{size} to resize #{width}x#{height} by #{geometry}" do
        expect(input_args(geometry, width, height)).to eq "-define jpeg:size=#{size}"
      end
    end

    it 'asks for nothing when a side of the reduced size would be zero' do
      expect(input_args('100x>', 10000, 1)).to be_nil
      expect(input_args('x100>', 1, 10000)).to be_nil
    end

    it 'asks for nothing when identify reports a zero width or height' do
      expect(input_args('900x>', 0, 3000)).to be_nil
      expect(input_args('900x>', 4000, 0)).to be_nil
    end

    it 'asks for nothing when the output needs the whole source' do
      [['900x>', 1000, 800], ['2000x', 1000, 800], ['1300x1300^', 1200, 900], ['500x500#', 640, 480]].each do |geometry, width, height|
        expect(input_args(geometry, width, height)).to be_nil, geometry
      end
    end

    ['300x200<', '50x50%', '300x200!', '10000@', '0x200', '900x<', '900x^', '30x30+10+10', '30x30ne'].each do |geometry|
      it "decodes the whole JPEG for #{geometry}" do
        expect(input_args(geometry, 4000, 3000)).to be_nil
      end
    end

    it 'decodes another format as before' do
      expect(input_args('900x>', 4000, 3000, 'png')).to be_nil
    end

    it 'asks for a size by the encoded sides of a JPEG the job does not orient' do
      expect(input_args('900x>', 1800, 1200, orientation: 'RightTop')).to eq '-define jpeg:size=900x600'
    end

    it 'keeps the format and the frame' do
      source('jpeg', [4000, 3000])
      expect(::Dragonfly::ImageMagick::Commands).to receive(:convert)
        .with(content, anything, hash_including('format' => 'webp', 'frame' => 1))

      processor.call(content, '900x>', decode.merge('format' => 'webp', 'frame' => 1))
    end

  end

  describe 'with ImageMagick' do

    let(:convert)  { app.env[:convert_command].to_s }
    let(:identify) { app.env[:identify_command].to_s }
    let(:dir)      { Dir.mktmpdir }
    let(:upstream) { ::Dragonfly::ImageMagick::Processors::Thumb.new }

    before { skip 'ImageMagick is not installed' unless File.exist?(convert) && File.exist?(identify) }
    after  { FileUtils.remove_entry(dir) if File.exist?(dir) }

    def image(name, size)
      File.join(dir, name).tap { |path| system(convert, '-size', size, 'gradient:red-blue', path, exception: true) }
    end

    def processed(processor, path, geometry, opts = {})
      ::Dragonfly::Content.new(app, File.new(path)).tap { |content| processor.call(content, geometry, opts) }
    end

    # takes the content itself, so its temporary file lives while it is read
    def read(target, format, define = nil)
      path = target.respond_to?(:path) ? target.path : target
      Open3.capture2(identify, *(define ? ['-define', define] : []), '-format', format, path).first
    end

    it 'processes a job without the option exactly as Dragonfly does' do
      jpeg = image('photo.jpg', '4000x3000')

      expect(read(processed(processor, jpeg, '900x>'), '%wx%h %#')).to eq read(processed(upstream, jpeg, '900x>'), '%wx%h %#')
    end

    accepted = %w(
      40x30 40x x30 40x30> 40x> x30> 40x30< 40x< x100< 100x100< 0x30> 0x30<
      40x30^ 40x^ x30^ 0x30^ 40x0^ 40x30! 40x! x30! x! 50x50% 50x% x50% 150x% x%
      1200@ 1@ 2400@ x 0x0 0x30 40x0
      40x30# 40x30#nw 40x30#n 40x30#ne 40x30#w 40x30#c 40x30#e 40x30#sw 40x30#s 40x30#se 0x0# 0x30#
      20x20+5+5 20x20-5-5 20x20+5 20x20nw 20x20c 20x20xx 0x0+0+0 0x20+0+0
    )

    # Preserve Dragonfly behavior, including accepted degenerate sizes.
    accepted.each do |geometry|
      it "runs #{geometry} as Dragonfly does, with the decode option and without" do
        png      = image('source.png', '60x40')
        expected = read(processed(upstream, png, geometry), '%wx%h %#')

        expect([{}, decode].map { |opts| read(processed(processor, png, geometry, opts), '%wx%h %#') }).to eq [expected] * 2
      end
    end

    def sizes(target)
      read(target, '%w %h').split.map(&:to_i)
    end

    def photo(code)
      File.join(dir, 'photo.jpg').tap do |path|
        system(convert, '-size', '1800x1200', 'gradient:red-blue', '-fill', 'lime', '-draw', 'rectangle 0,0 299,199', path, exception: true)
        ExifOrientation.write(path, code)
      end
    end

    def upright(jpeg)
      File.join(dir, 'upright.miff').tap { |path| system(convert, jpeg, '-auto-orient', '+repage', path, exception: true) }
    end

    (2..8).each do |code|
      it "resizes an EXIF #{code} JPEG as Dragonfly resizes the image upright" do
        jpeg = photo(code)

        %w(900x> 600x200# 600x200#nw 300x300+100+50 300x300ne).each do |geometry|
          expect(read(processed(processor, jpeg, geometry, 'orient' => true, 'format' => 'png'), '%wx%h %#'))
            .to eq(read(processed(upstream, upright(jpeg), geometry, 'format' => 'png'), '%wx%h %#')), geometry
        end
      end
    end

    (5..8).each do |code|
      it "fills an EXIF #{code} JPEG decoded smaller as the image upright fills" do
        jpeg     = photo(code)
        expected = size_and_red(processed(upstream, upright(jpeg), '600x200#'))

        expect(size_and_red(processed(processor, jpeg, '600x200#', decode.merge('orient' => true))))
          .to match [expected.first, be_within(0.01).of(expected.last)]
      end
    end

    frames = %w(10x20 100x1000 1000x100).flat_map do |size|
      ["#{size}+0+0", "#{size}+3+4", '100x50+5+7', '1x1+500+0', '1x1+0+500', '3000x50+0+0'].map { |page| [size, page] }
    end

    def layout(target)
      read(target, '%w %h %W %H %X %Y').split.map(&:to_i)
    end

    orientations = %w(Undefined TopLeft TopRight BottomRight BottomLeft LeftTop RightTop RightBottom LeftBottom)

    orientations.product(frames).each do |orientation, (size, page)|
      it "leaves a #{size} frame on a #{page} canvas, #{orientation}, as Steam bounds it" do
        miff = File.join(dir, 'frame.miff')
        system(convert, '-size', size, 'xc:red', '-repage', page, '-orient', orientation, miff, exception: true)
        width, height = size.split('x').map(&:to_i)
        sides    = %w(LeftTop RightTop RightBottom LeftBottom).include?(orientation) ? [height, width] : [width, height]
        expected = %w(Undefined TopLeft).include?(orientation) ? layout(miff) : [*sides, *sides, 0, 0]

        expect(layout(processed(processor, miff, '10000x10000>', 'orient' => true, 'format' => 'miff'))).to eq expected
      end
    end

    it 'reads the orientation of each frame, and each frame as ImageMagick orients it' do
      a, b, both = %w(a.miff b.miff both.miff).map { |name| File.join(dir, name) }
      system(convert, '-size', '60x60', 'xc:red', '-orient', 'TopLeft', a, exception: true)
      system(convert, '-size', '180x60', 'xc:blue', '-orient', 'RightTop', b, exception: true)
      system(convert, a, b, both, exception: true)
      image  = ::Dragonfly::Content.new(app, File.new(both))
      reader = Locomotive::Steam::ImageResizerService::SourceImage

      expect(reader.new.call(image)['frames'].map { |frame| frame['orientation'] }).to eq %w(TopLeft RightTop)
      expect(reader.oriented(image, nil, nil)['frames'].map { |frame| frame.values_at('size', 'source_orientation') })
        .to eq [[[60, 60], 'TopLeft'], [[60, 180], 'RightTop']]
      expect(reader.oriented(image, 1, nil)['frames'].map { |frame| frame['size'] }).to eq [[60, 180]]
    end

    it 'measures a JPEG as ImageMagick orients it at the size it decodes to' do
      jpeg = ::Dragonfly::Content.new(app, File.new(image('photo.jpg', '1800x1200').tap { |path| ExifOrientation.write(path, 6) }))

      expect(Locomotive::Steam::ImageResizerService::SourceImage.oriented(jpeg, nil, '-define jpeg:size=450x300')['frames']
        .map { |frame| frame['size'] }).to eq [[300, 450]]
    end

    %w(jpg webp).each do |format|
      it "writes the #{format} one ImageMagick command writes, at the quality of the JPEG it orients" do
        jpeg = File.join(dir, 'photo.jpg').tap do |path|
          system(convert, '-size', '400x300', 'gradient:red-blue', '-quality', '80', path, exception: true)
          ExifOrientation.write(path, 6)
        end
        direct = File.join(dir, "direct.#{format}")
        system(convert, jpeg, '-auto-orient', '+repage', '-resize', '90x', direct, exception: true)

        expect(processed(processor, jpeg, '90x', 'orient' => true, 'format' => format).data).to eq File.binread(direct)
      end
    end

    it 'orients and bounds an EXIF 6 WebP, whose orientation a ping leaves out' do
      jpeg = image('photo.jpg', '120x40').tap { |path| ExifOrientation.write(path, 6) }
      webp = File.join(dir, 'photo.webp').tap { |path| system(convert, jpeg, path, exception: true) }
      allow(Locomotive::Steam.configuration).to receive(:image_resizer_max_side).and_return(100)

      expect { processed(processor, webp, '60x', 'orient' => true) }
        .to raise_error(Locomotive::Steam::ImageResizerService::Shell::RefusedJob, 'Steam does not resize to this size')
      expect(read(processed(processor, webp, '30x', 'orient' => true), '%wx%h')).to eq '30x90'
    end

    def sequence
      turned, placed, both = %w(turned.miff placed.miff both.miff).map { |name| File.join(dir, name) }
      system(convert, '-size', '10x20', 'xc:lime', '-repage', '100x20+0+0', '-orient', 'RightTop', turned, exception: true)
      system(convert, '-size', '10x10', 'xc:blue', '-repage', '100x10+80+0', '-orient', 'TopLeft', placed, exception: true)
      system(convert, turned, placed, both, exception: true)
      both
    end

    def frames_of(target)
      read(target, '%w %h %W %H %X %Y ').split.map(&:to_i).each_slice(6).to_a
    end

    it 'orients each frame of a sequence as ImageMagick does, an untagged frame keeping its place' do
      frames = frames_of(processed(processor, sequence, '10000x10000>', 'orient' => true, 'format' => 'miff'))

      expect([frames.size, frames.first.first(2), frames.last]).to eq [2, [20, 10], [10, 10, 100, 10, 80, 0]]
    end

    it 'keeps the delays, disposal and loop of an animation it orients' do
      gif = File.join(dir, 'animation.gif')
      system(convert, '-delay', '10', '-dispose', 'Background', '-size', '20x10', 'xc:red',
             '-delay', '30', '-dispose', 'None', '-size', '20x10', 'xc:blue', '-loop', '3', gif, exception: true)
      timing = lambda do |target|
        path = target.respond_to?(:path) ? target.path : target
        [read(target, '%T %D,'), Open3.capture2(identify, '-verbose', path).first[/Iterations: \d+/]]
      end

      expect(timing.call(processed(processor, gif, '10x5', 'orient' => true))).to eq ['10 Background,30 None,', 'Iterations: 3']
    end

    it 'orients only the frame a job names' do
      expect(frames_of(processed(processor, sequence, '10000x10000>', 'orient' => true, 'frame' => 0, 'format' => 'miff')))
        .to eq [[20, 10, 20, 10, 0, 0]]
    end

    it 'resizes a JPEG with no orientation the same with the orient option and without' do
      jpeg = image('photo.jpg', '1800x1200')

      expect(read(processed(processor, jpeg, '900x>', decode.merge('orient' => true)), '%wx%h %#'))
        .to eq read(processed(processor, jpeg, '900x>', decode), '%wx%h %#')
    end

    def within?(actual, bound)
      actual.zip(bound).all? { |size, limit| size <= limit }
    end

    # Degenerate dimensions and crop offsets use conservative bounds.
    loose = %w(x 0x0 0x30 40x0 0x30> 0x30^ 40x0^ 0x0# 0x30# 20x20+5+5 20x20-5-5 20x20+5)

    %w(60x40 40x60 7x3).product(accepted).each do |dims, geometry|
      it "bounds #{geometry} from #{dims} at what it makes#{' or above' if loose.include?(geometry)}" do
        png    = image("source-#{dims}.png", dims)
        bound  = Locomotive::Steam::ImageResizerService::Geometry.sizes(geometry, *dims.split('x').map(&:to_i))
        actual = [sizes(processed(processor, png, geometry))]

        if (fill = geometry[/\A(\d+x\d+)#/, 1])
          filled = File.join(dir, 'filled.png').tap { |path| system(convert, png, '-resize', "#{fill}^^", path, exception: true) }
          actual.unshift(sizes(filled))
        end

        expect(actual.zip(bound).all? { |size, limit| within?(size, limit) }).to be(true), "#{actual} past #{bound}"
        next if loose.include?(geometry)

        expect(actual.zip(bound).all? { |size, limit| within?(limit, size.map(&:succ)) }).to be(true), "#{bound} above #{actual}"
      end
    end

    # The decoder rounds the reduced size up, so the side the geometry derives
    # from the aspect ratio may differ by a pixel; the side it sets does not.
    {
      '900x>'      => ['4001x3001', { 0 => 900 }],             # 2/8
      '300x200'    => ['4001x3001', { 1 => 200 }],             # 1/8
      'x323>'      => ['4001x3001', { 1 => 323 }],             # 1/8
      '2292x1125#' => ['4001x3001', { 0 => 2292, 1 => 1125 }]  # 5/8
    }.each do |geometry, (source, set_sides)|
      it "decodes #{source} for #{geometry} at no less than the output, keeping the side it sets" do
        jpeg = image('photo.jpg', source)
        args = nil
        allow(::Dragonfly::ImageMagick::Commands).to receive(:convert).and_wrap_original do |original, content, command, opts|
          args = opts['input_args'] if opts.key?('input_args')
          original.call(content, command, opts)
        end

        result  = read(processed(processor, jpeg, geometry, decode), '%w %h').split.map(&:to_i)
        decoded = read(jpeg, '%w %h', args.split.last).split.map(&:to_i)
        filled  = read(processed(upstream, jpeg, geometry.sub('#', '^')), '%w %h').split.map(&:to_i)
        full    = read(processed(upstream, jpeg, geometry), '%w %h').split.map(&:to_i)

        expect(args).to start_with '-define jpeg:size='
        expect(decoded.zip(filled).all? { |d, n| d >= n }).to be(true), "decoded #{decoded} for #{filled}"
        expect(decoded.zip(source.split('x').map(&:to_i)).all? { |d, s| d <= s }).to be(true), "decoded #{decoded}"
        expect(result.zip(full).all? { |r, f| (r - f).abs <= 1 }).to be(true), "resized #{result}, full decode #{full}"
        set_sides.each { |side, size| expect(result[side]).to eq size }
      end
    end

    {
      '900x>'      => '4001x3001',
      '300x200'    => '4001x3001',
      'x323>'      => '4001x3001',
      '300x200^'   => '4003x2999',
      '900x'       => '4007x3005',
      '2292x1125#' => '4001x3001'
    }.each do |geometry, source|
      it "bounds #{geometry} on a #{source} JPEG at the size it decodes to" do
        jpeg = image('photo.jpg', source)
        args = nil
        allow(::Dragonfly::ImageMagick::Commands).to receive(:convert).and_wrap_original do |original, content, command, opts|
          args = opts['input_args'] if opts.key?('input_args')
          original.call(content, command, opts)
        end

        result  = sizes(processed(processor, jpeg, geometry, decode))
        hint    = args.split('=').last.split('x').map(&:to_i)
        decoded = read(jpeg, '%w %h', args.split.last).split.map(&:to_i)
        bound   = Locomotive::Steam::ImageResizerService::Geometry.sizes(geometry, *decoded)

        expect(described_class.decoded_sizes(*source.split('x').map(&:to_i), hint)).to include(decoded)
        expect(within?(result, bound.last)).to be(true), "#{result} past #{bound.last}"
      end
    end

    [{}, { 'decode' => 'jpeg-1x-v1' }].each do |opts|
      it "reads a JPEG once and converts it once, #{opts.empty? ? 'without' : 'with'} the decode option" do
        jpeg     = image('photo.jpg', '4000x3000')
        commands = []
        allow(app.shell).to receive(:run_command).and_wrap_original do |original, command|
          commands << (command.start_with?(identify) ? :identify : :convert)
          original.call(command)
        end

        processed(processor, jpeg, '900x>', opts)

        expect(commands).to eq %i(identify convert)
      end
    end

    def size_and_red(content)
      Open3.capture2(identify, '-format', '%wx%h %[fx:mean.r]', content.path).first.split.then { |size, red| [size, red.to_f] }
    end

    it 'crops a JPEG resized to fill at the place its gravity names' do
      jpeg = image('photo.jpg', '4000x3000') # red at the top, blue at the bottom

      north, south = %w(600x200#n 600x200#s).map do |geometry|
        size, red = size_and_red(processed(processor, jpeg, geometry, decode))
        expected_size, expected_red = size_and_red(processed(upstream, jpeg, geometry))

        expect([size, expected_size]).to eq %w(600x200 600x200)
        expect(red).to be_within(0.01).of(expected_red)
        red
      end

      expect(north - south).to be > 0.5
    end

    it 'crops a JPEG at its full size' do
      jpeg = image('photo.jpg', '4000x3000')

      expect(read(processed(processor, jpeg, '100x100+50+50', decode), '%wx%h %#')).to eq read(processed(upstream, jpeg, '100x100+50+50'), '%wx%h %#')
    end

    it 'resizes a PNG as before' do
      png = image('logo.png', '4000x3000')

      expect(read(processed(processor, png, '900x>', decode), '%wx%h %#')).to eq read(processed(upstream, png, '900x>'), '%wx%h %#')
    end

  end

end
