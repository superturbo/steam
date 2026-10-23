require 'spec_helper'
require 'open3'

describe Locomotive::Steam::ImageResizerService::Thumb do

  let(:app)       { ::Dragonfly.app(:steam) }
  let(:content)   { ::Dragonfly::Content.new(app, 'image') }
  let(:processor) { described_class.new }
  let(:decode)    { { 'decode' => 'jpeg-1x-v1' } }

  describe 'a job without the decode option' do

    it 'is processed as Dragonfly processes it, without reading the image first' do
      expect(content).not_to receive(:analyse)
      expect(::Dragonfly::ImageMagick::Commands).to receive(:convert)
        .with(content, processor.args_for_geometry('900x>'), { 'format' => 'webp', 'frame' => 1 })

      processor.call(content, '900x>', 'format' => 'webp', 'frame' => 1)
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

    def input_args(geometry, width, height, format = 'jpeg')
      allow(content).to receive(:analyse).with(:image_properties).and_return('format' => format, 'width' => width, 'height' => height)
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

    it 'keeps the format and the frame' do
      allow(content).to receive(:analyse).with(:image_properties).and_return('format' => 'jpeg', 'width' => 4000, 'height' => 3000)
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

    # Preserve Dragonfly behavior, including accepted degenerate sizes.
    %w(
      40x30 40x x30 40x30> 40x> x30> 40x30< 40x< x100< 100x100< 0x30> 0x30<
      40x30^ 40x^ x30^ 0x30^ 40x0^ 40x30! 40x! x30! x! 50x50% 50x% x50% 150x% x%
      1200@ 1@ 2400@ x 0x0 0x30 40x0
      40x30# 40x30#nw 40x30#n 40x30#ne 40x30#w 40x30#c 40x30#e 40x30#sw 40x30#s 40x30#se 0x0# 0x30#
      20x20+5+5 20x20-5-5 20x20+5 20x20nw 20x20c 20x20xx 0x0+0+0 0x20+0+0
    ).each do |geometry|
      it "runs #{geometry} as Dragonfly does, with the decode option and without" do
        png      = image('source.png', '60x40')
        expected = read(processed(upstream, png, geometry), '%wx%h %#')

        expect([{}, decode].map { |opts| read(processed(processor, png, geometry, opts), '%wx%h %#') }).to eq [expected] * 2
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
