require File.dirname(__FILE__) + '/../integration_helper'
require 'open3'

describe "The image formats resize jobs read and write under Steam's ImageMagick policy" do

  let(:resizer)  { ::Dragonfly.app(:steam) }
  let(:convert)  { resizer.env[:convert_command].to_s }
  let(:identify) { resizer.env[:identify_command].to_s }
  let(:dir)      { Dir.mktmpdir }

  before { skip 'ImageMagick is not installed' unless File.exist?(convert) && File.exist?(identify) }
  after  { FileUtils.remove_entry(dir) if File.exist?(dir) }

  # sources are made with ImageMagick outside Steam, under the system policy
  def made(name, *arguments)
    File.join(dir, name).tap { |path| system(convert, *arguments, path, exception: true) }
  end

  def written(name, text)
    File.join(dir, name).tap { |path| File.write(path, text) }
  end

  def photo = made('photo.jpg', '-size', '120x90', 'gradient:red-blue')

  def pdf = File.binread(File.join(Locomotive::Steam::ImageResizerService::Shell::SAMPLES_PATH, Locomotive::Steam::ImageResizerService::Shell::REFUSED['PDF']))

  def jobs(path)
    file = resizer.fetch_file(path)
    {
      new:     file.thumb('30x20#', 'decode' => 'jpeg-1x-v1'),
      earlier: file.thumb('30x20#'),
      convert: file.thumb('30x20#', 'decode' => 'jpeg-1x-v1').process(:convert, '-quality 70')
    }
  end

  def format_of(content)
    Open3.capture2(identify, '-format', '%m', "#{content.path}[0]").first
  end

  # what this ImageMagick reads and writes with its own modules; another host may differ
  def supported?(format)
    Open3.capture2(convert, '-list', 'format').first.match?(/^\s*#{format}\*?\s+\S+\s+rw/)
  end

  # refused by the policy, or no longer recognised as ImageMagick 6 does
  def refused?(job)
    job.apply
    false
  rescue Dragonfly::Shell::CommandFailed => e
    e.message.match?(Locomotive::Steam::ImageResizerService::Shell::REFUSAL) or raise
  end

  describe 'an allowed source' do

    {
      'photo.jpg' => ['JPEG', '-size', '120x90', 'gradient:red-blue'],
      'logo.png'  => ['PNG',  '-size', '120x90', 'gradient:red-blue'],
      'anim.gif'  => ['GIF',  '-size', '120x90', 'xc:red', 'xc:blue', '-set', 'delay', '20'],
      'shot.webp' => ['WEBP', '-size', '120x90', 'gradient:red-blue']
    }.each do |name, (format, *arguments)|
      it "is resized as #{format} by a new and an earlier URL and the :convert step" do
        skip "this ImageMagick does not read and write #{format}" unless %w(JPEG PNG).include?(format) || supported?(format)
        path = made(name, *arguments)

        jobs(path).each do |kind, job|
          expect(format_of(job.apply.content)).to eq(format), kind.to_s
        end
      end
    end

  end

  describe 'a raster source in another format' do

    {
      'icon.bmp'  => ['BMP',  '-size', '60x40', 'xc:red'],
      'scan.tiff' => ['TIFF', '-size', '60x40', 'xc:red'],
      'logo.ico'  => ['ICO',  '-size', '32x32', 'xc:red']
    }.each do |name, (format, *arguments)|
      it "#{name} is resized as #{format} by a new and an earlier URL and the :convert step" do
        skip "this ImageMagick does not read and write #{format}" unless supported?(format)
        path = made(name, *arguments)

        jobs(path).each do |kind, job|
          expect(format_of(job.apply.content)).to eq(format), kind.to_s
        end
      end
    end

  end

  describe 'a document, script or text source' do

    {
      'doc.pdf'       => -> { written('doc.pdf', pdf) },
      'doc.ps'        => -> { written('doc.ps', "%!PS-Adobe-3.0\nnewpath 0 0 moveto 60 40 lineto stroke showpage\n") },
      'doc.eps'       => -> { written('doc.eps', "%!PS-Adobe-3.0 EPSF-3.0\n%%BoundingBox: 0 0 60 40\nnewpath 0 0 moveto 60 40 lineto stroke\n") },
      'pdf named.jpg' => -> { written('named.jpg', pdf) },
      'drawing.svg'   => -> { written('drawing.svg', '<svg xmlns="http://www.w3.org/2000/svg" width="60" height="40"><rect width="60" height="40"/></svg>') },
      'shapes.mvg'    => -> { written('shapes.mvg', "viewbox 0 0 60 40\nfill red rectangle 0,0 30,20\n") },
      'note.txt'      => -> { written('note.txt', "plain text\n") }
    }.each do |name, source|
      it "#{name} is refused by a new and an earlier URL and the :convert step" do
        path = instance_exec(&source)

        jobs(path).each do |kind, job|
          expect(refused?(job)).to be(true), kind.to_s
        end
      end
    end

  end

  # a stand-in for the program, found on the PATH the host gives ImageMagick
  describe 'a format ImageMagick reads through an external program' do

    let(:ran) { File.join(dir, 'ran') }
    let(:bin) do
      File.join(dir, 'bin').tap do |folder|
        FileUtils.mkdir_p(folder)
        png = made('decoded.png', '-size', '20x10', 'xc:red')
        File.write(File.join(folder, 'bpgdec'), "#!/bin/sh\ntouch #{ran}\nwhile [ \"$1\" != -o ]; do shift; done\ncp #{png} \"$2\"\n")
        File.chmod(0o755, File.join(folder, 'bpgdec'))
      end
    end

    around do |example|
      kept = ENV['PATH']
      ENV['PATH'] = "#{bin}:#{kept}"
      example.run
    ensure
      ENV['PATH'] = kept
    end

    it 'is refused without running the program' do
      path = File.join(dir, 'image.bpg').tap { |file| File.binwrite(file, "BPG\xFBjunkjunkjunk") }

      jobs(path).each do |kind, job|
        expect(refused?(job)).to be(true), kind.to_s
      end
      expect(File.exist?(ran)).to be false
    end

  end

  describe 'a source named for another format' do

    it 'is written in the format its name gives when that format is allowed' do
      path = File.join(dir, 'logo.jpg').tap { |target| FileUtils.mv(made('logo.png', '-size', '120x90', 'gradient:red-blue'), target) }

      expect(format_of(jobs(path)[:earlier].apply.content)).to eq 'JPEG'
    end

    it 'is refused when its name gives a format that is not allowed' do
      path = File.join(dir, 'logo.pdf').tap { |target| FileUtils.mv(made('logo.png', '-size', '120x90', 'gradient:red-blue'), target) }

      expect(refused?(jobs(path)[:earlier])).to be true
    end

  end

  describe 'ImageMagick arguments of the :convert step' do

    it 'cannot read a file indirectly' do
      secret = written('secret.txt', 'sentinel')

      expect(refused?(resizer.fetch_file(photo).process(:convert, "-set comment @#{secret}"))).to be true
    end

    it 'cannot read an inline image' do
      inline = "inline:data:image/png;base64,#{[File.binread(File.join(Locomotive::Steam::ImageResizerService::Shell::SAMPLES_PATH, Locomotive::Steam::ImageResizerService::Shell::SAMPLE))].pack('m0')}"

      expect(refused?(resizer.fetch_file(photo).process(:convert, "#{inline} -append"))).to be true
    end

    it 'cannot run an MSL script' do
      written_by_script = File.join(dir, 'by-script.png')
      script = written('script.msl', %(<?xml version="1.0"?><image><read filename="#{photo}"/><write filename="#{written_by_script}"/></image>))

      expect(refused?(resizer.fetch_file(photo).process(:convert, "msl:#{script} -append"))).to be true
      expect(File.exist?(written_by_script)).to be false
    end

    it 'cannot draw an MVG file' do
      drawing = written('shapes.mvg', "viewbox 0 0 60 40\nfill red rectangle 0,0 30,20\n")

      expect(refused?(resizer.fetch_file(photo).process(:convert, "mvg:#{drawing} -append"))).to be true
    end

    it "cannot draw SVG with ImageMagick's own renderer" do
      svg = written('drawing.svg', '<svg xmlns="http://www.w3.org/2000/svg" width="60" height="40"><rect width="60" height="40"/></svg>')

      expect(refused?(resizer.fetch_file(photo).process(:convert, "msvg:#{svg} -append"))).to be true
    end

    it 'cannot write a format that is not allowed' do
      copy = File.join(dir, 'copy.pdf')

      expect(refused?(resizer.fetch_file(photo).process(:convert, "-write #{copy}"))).to be true
      expect(File.exist?(copy) ? File.binread(copy, 4) : nil).not_to eq '%PDF'
    end

  end

end
