require File.dirname(__FILE__) + '/../integration_helper'
require 'open3'

describe 'Resize jobs' do

  include Rack::Test::Methods

  let(:configuration) { Locomotive::Steam.configuration }
  let(:resizer)       { ::Dragonfly.app(:steam) }
  let(:image)         { File.join(default_fixture_site_path, 'public/images/nav_on.png') }
  let(:job)           { resizer.fetch_file(image) }

  def app
    run_server
  end

  def resize_service
    Locomotive::Steam::ImageResizerService.new(resizer, site: Locomotive::Steam::Site.new(_id: 'site-1'))
  end

  def url_signed_with(signing_key)
    kept, resizer.secret = resizer.secret, signing_key
    job.url
  ensure
    resizer.secret = kept
  end

  # The Dragonfly key is global: restore the suite's key once the stubs are gone.
  around do |example|
    example.run
    Locomotive::Steam::Initializers::Dragonfly.new.run
  end

  before do
    allow(configuration).to receive_messages(mode: mode, image_resizer_secret: key)
    Locomotive::Steam::Initializers::Dragonfly.new.run
  end

  shared_examples 'a server running only the jobs it signed' do

    it 'serves a job it signed' do
      get job.url

      expect(last_response.status).to eq 200
      expect(last_response.body).to eq File.binread(image)
    end

    it 'serves a resized image from a trusted remote source' do
      server = TCPServer.new('127.0.0.1', 0)
      port   = server.addr[1]
      Thread.new do
        client = server.accept
        client.gets("\r\n\r\n")
        body = File.binread(image)
        client.write("HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
        client.close
      rescue IOError, SystemCallError
      end
      allow(configuration).to receive(:image_resizer_remote_source_prefix).and_return("http://127.0.0.1:#{port}/sites/")

      url = resize_service.resize("http://127.0.0.1:#{port}/sites/1/banner.png", '4x4')
      get url

      expect(last_response.status).to eq 200
      expect(last_response.content_type).to eq 'image/png'
    ensure
      server&.close
    end

    [
      'http://other.example.com/sites/1/banner.png',
      'https://cdn.example.com/sites/1/banner.png',
      'http://cdn.example.com:8080/sites/1/banner.png',
      'http://cdn.example.com/sites-x/banner.png',
      'http://169.254.169.254/latest/meta-data/banner.png'
    ].each do |source|
      it "refuses a signed fetch_url job for #{source}" do
        allow(configuration).to receive(:image_resizer_remote_source_prefix).and_return('http://cdn.example.com/sites/')

        get resizer.fetch_url(source).url

        expect(last_response.status).to eq 403
      end
    end

    it 'reads no file outside the asset path, even for a job it signed' do
      Dir.mktmpdir('public') do |outside|
        File.write(File.join(outside, 'secret.png'), 'secret')

        get resizer.fetch_file(File.join(outside, 'secret.png')).url

        expect(last_response.status).to eq 403
        expect(last_response.headers['cache-control']).to eq 'no-store'
        expect(last_response.body).not_to include 'secret'
      end
    end

    it 'reads no file a link points out to after the URL was issued' do
      Dir.mktmpdir do |root|
        Dir.mktmpdir do |outside|
          allow(configuration).to receive(:asset_path).and_return(root)
          FileUtils.cp(image, File.join(root, 'banner.png'))
          File.write(File.join(outside, 'secret.png'), 'secret')
          link = File.join(root, 'current.png')
          File.symlink(File.join(root, 'banner.png'), link)

          url = resize_service.resize('/current.png', '4x4')
          expect(url).to start_with '/steam/dynamic/'

          File.unlink(link)
          File.symlink(File.join(outside, 'secret.png'), link)

          get url
          expect(last_response.status).to eq 403
          expect(last_response.body).not_to include 'secret'

          head url
          expect(last_response.status).to eq 403
        end
      end
    end

    it 'refuses a job signed with the public placeholder' do
      expect_any_instance_of(Dragonfly::Job).not_to receive(:apply)

      get url_signed_with('please change it')
      expect(last_response.status).to eq 400
      expect(last_response.headers['cache-control']).to eq 'no-store'

      head url_signed_with('please change it')
      expect(last_response.status).to eq 400
    end

    it 'answers a method other than GET and HEAD with 405, kept by no cache' do
      post job.url

      expect(last_response.status).to eq 405
      expect(last_response.headers['cache-control']).to eq 'no-store'
    end

  end

  context 'with a configured key' do

    let(:mode) { :production }
    let(:key)  { 'a deployment key' }

    it_behaves_like 'a server running only the jobs it signed'

  end

  context 'in test mode without a key' do

    let(:mode) { :test }
    let(:key)  { nil }

    it_behaves_like 'a server running only the jobs it signed'

  end

  context 'two sites' do

    let(:mode) { :production }
    let(:key)  { 'a deployment key' }

    def service_for(id)
      Locomotive::Steam::ImageResizerService.new(resizer, site: Locomotive::Steam::Site.new(_id: id))
    end

    it "names the site a request's domain finds, rendering as a page does" do
      allow(configuration).to receive(:asset_path).and_return(File.join(default_fixture_site_path, 'public'))
      services = Locomotive::Steam::Services.build_instance(Rack::Request.new(Rack::MockRequest.env_for('http://localhost/')))

      url = services.image_resizer.resize('/images/nav_on.png', '4x4')

      expect(::Dragonfly::Job.deserialize(url.split('/')[3], resizer).steps.last.args.last['site']).to eq services.current_site._id.to_s
    end

    it "resizes one site's file for another, under a job naming the rendering site" do
      Dir.mktmpdir do |root|
        allow(configuration).to receive(:asset_path).and_return(root)
        FileUtils.mkdir_p(File.join(root, 'sites/b'))
        FileUtils.cp(image, File.join(root, 'sites/b/photo.png'))

        for_a = service_for('a').resize('/sites/b/photo.png', '4x4')
        for_b = service_for('b').resize('/sites/b/photo.png', '4x4')
        expect(for_a).not_to eq for_b

        get for_a
        expect(last_response.status).to eq 200
      end
    end

  end

  context 'an ImageMagick command that runs past its timeout' do

    let(:mode) { :production }
    let(:key)  { 'a deployment key' }
    let(:dir)  { Dir.mktmpdir }

    before do
      skip 'ImageMagick is not installed' unless File.exist?(resizer.env[:convert_command].to_s)
      allow(configuration).to receive(:image_magick_command_timeout).and_return(0.5)
      Locomotive::Steam::Initializers::Dragonfly.new.run
      resizer.env[:convert_command] = File.join(dir, 'convert').tap do |path|
        File.write(path, "#!/bin/sh\nsleep 30\n")
        File.chmod(0o755, path)
      end
      allow(Dragonfly).to receive(:warn)
    end

    after { FileUtils.remove_entry(dir) }

    it 'answers 500, kept by no cache, for a new and an earlier URL, and logs no command' do
      [job.thumb('4x4', 'decode' => 'jpeg-1x-v1').url, job.thumb('4x4').url].each do |url|
        get url

        expect(last_response.status).to eq 500
        expect(last_response.headers['cache-control']).to eq 'no-store'
      end
      expect(Dragonfly).to have_received(:warn).with('caught error - ImageMagick command ran past 0.5s').twice
    end

  end

  context 'an earlier URL a client has cached' do

    let(:mode) { :production }
    let(:key)  { 'a deployment key' }

    before { skip 'ImageMagick is not installed' unless File.exist?(resizer.env[:convert_command].to_s) }

    it 'is answered 304 from its ETag before any ImageMagick command runs' do
      job = resizer.fetch_file(image).thumb('4x4')
      allow(resizer.shell).to receive(:run).and_call_original

      get job.url, {}, 'HTTP_IF_NONE_MATCH' => %("#{job.signature}")

      expect(last_response.status).to eq 304
      expect(resizer.shell).not_to have_received(:run)

      get job.url

      expect(last_response.status).to eq 200
      expect(resizer.shell).to have_received(:run).at_least(:once)
    end

  end

  context 'a source or an argument ImageMagick refuses' do

    let(:mode) { :production }
    let(:key)  { 'a deployment key' }
    let(:pdf)  { File.join(Locomotive::Steam::ImageResizerService::Shell::SAMPLES_PATH, 'refused.pdf') }

    before do
      skip 'ImageMagick is not installed' unless File.exist?(resizer.env[:convert_command].to_s)
      allow(Dragonfly).to receive(:warn)
    end

    it 'answers 404, kept by no cache, for a new and an earlier URL' do
      Dir.mktmpdir do |root|
        allow(configuration).to receive(:asset_path).and_return(root)
        source = resizer.fetch_file(File.join(root, 'doc.pdf').tap { |path| FileUtils.cp(pdf, path) })

        [source.thumb('4x4', 'decode' => 'jpeg-1x-v1').url, source.thumb('4x4').url].each do |url|
          %i(get head).each do |verb|
            send(verb, url)

            expect(last_response.status).to eq(404), "#{verb} #{url}"
            expect(last_response.headers['cache-control']).to eq 'no-store'
          end
        end
        expect(Dragonfly).to have_received(:warn).with(/\AImageMagick refused the source or an argument: /).exactly(4).times
      end
    end

    it 'answers 404 for a :convert step on a source ImageMagick refuses' do
      Dir.mktmpdir do |root|
        allow(configuration).to receive(:asset_path).and_return(root)
        source = resizer.fetch_file(File.join(root, 'doc.pdf').tap { |path| FileUtils.cp(pdf, path) })

        get source.process(:convert, '-strip').url

        expect(last_response.status).to eq 404
        expect(last_response.headers['cache-control']).to eq 'no-store'
      end
    end

    it 'answers 404 for a :convert step with a script argument' do
      Dir.mktmpdir do |folder|
        script = File.join(folder, 'script.msl').tap { |path| File.write(path, '<?xml version="1.0"?><image/>') }

        get job.thumb('4x4').process(:convert, "msl:#{script} -append").url

        expect(last_response.status).to eq 404
        expect(last_response.headers['cache-control']).to eq 'no-store'
      end
    end

    it 'answers 404 for an earlier :convert step with arguments Steam does not run, and writes nothing' do
      Dir.mktmpdir do |folder|
        copy = File.join(folder, 'copy.png')

        get job.thumb('4x4').process(:convert, "-quality 70 -write #{copy}").url

        expect(last_response.status).to eq 404
        expect(last_response.headers['cache-control']).to eq 'no-store'
        expect(File.exist?(copy)).to be false
      end
    end

    it 'answers 404 for an earlier :convert step that reads another image' do
      get job.thumb('4x4').process(:convert, "#{image} -append").url

      expect(last_response.status).to eq 404
    end

    it 'runs an earlier :convert step with the arguments the resize options produce' do
      get job.thumb('4x4').process(:convert, '-quality 70 -strip -interlace Plane -auto-orient').url

      expect(last_response.status).to eq 200
    end

    it 'keeps public caching for a resized image' do
      get job.thumb('4x4').url

      expect(last_response.status).to eq 200
      expect(last_response.headers['cache-control']).to eq 'public, max-age=31536000'
    end

  end

  context 'a job Steam does not run' do

    let(:mode) { :production }
    let(:key)  { 'a deployment key' }

    before { allow(Dragonfly).to receive(:warn) }

    %w(0@ 0x30! 0x0% 40x30#xx 20x20+5+5nw 50%).each do |geometry|
      it "answers 404, kept by no cache, for a new and an earlier URL resizing to #{geometry}" do
        [job.thumb(geometry, 'decode' => 'jpeg-1x-v1').url, job.thumb(geometry).url].each do |url|
          %i(get head).each do |verb|
            send(verb, url)

            expect(last_response.status).to eq(404), "#{verb} #{url}"
            expect(last_response.headers['cache-control']).to eq 'no-store'
          end
        end
        expect(Dragonfly).to have_received(:warn).with('Steam does not run this geometry').exactly(4).times
      end
    end

    it 'answers 404, kept by no cache, for an unknown decode option' do
      get job.thumb('4x4', 'decode' => 'jpeg-2x-v1').url

      expect(last_response.status).to eq 404
      expect(last_response.headers['cache-control']).to eq 'no-store'
      expect(Dragonfly).to have_received(:warn).with('Steam does not run this decode option')
    end

  end

  context 'a job past the size bounds' do

    let(:mode) { :production }
    let(:key)  { 'a deployment key' }

    before do
      skip 'ImageMagick is not installed' unless File.exist?(resizer.env[:convert_command].to_s)
      allow(Dragonfly).to receive(:warn)
    end

    def with_source(name, *image)
      Dir.mktmpdir do |root|
        allow(configuration).to receive(:asset_path).and_return(root)
        path = File.join(root, name).tap { |file| system(resizer.env[:convert_command].to_s, *image, file, exception: true) }

        yield resizer.fetch_file(path)
      end
    end

    def served_size
      Open3.capture2(resizer.env[:identify_command].to_s, '-format', '%wx%h ', '-', stdin_data: last_response.body, binmode: true).first.strip
    end

    it 'serves an output side of 5760 and refuses one of 5761, for a new and an earlier URL' do
      with_source('photo.jpg', '-size', '600x300', 'gradient:red-blue') do |source|
        %w(5760x 5761x).each do |geometry|
          [source.thumb(geometry, 'decode' => 'jpeg-1x-v1'), source.thumb(geometry)].each do |job|
            get job.url

            if geometry == '5760x'
              expect([last_response.status, served_size]).to eq [200, '5760x2880']
            else
              expect([last_response.status, last_response.headers['cache-control']]).to eq [404, 'no-store']
            end
          end
        end
        expect(Dragonfly).to have_received(:warn).with('Steam does not resize to this size').twice
      end
    end

    it 'bounds the only frame of a JPEG a frame index past it names, which ImageMagick resizes all the same' do
      with_source('photo.jpg', '-size', '600x300', 'gradient:red-blue') do |source|
        [{}, { 'decode' => 'jpeg-1x-v1' }].each do |opts|
          get source.thumb('5760x', opts.merge('frame' => 1)).url
          expect([last_response.status, served_size]).to eq [200, '5760x2880']

          get source.thumb('5761x', opts.merge('frame' => 1)).url
          expect([last_response.status, last_response.headers['cache-control']]).to eq [404, 'no-store']
        end
      end
    end

    it 'refuses a frame option ImageMagick would read as no frame index, and serves a whole one' do
      formats = Open3.capture2(resizer.env[:convert_command].to_s, '-list', 'format').first
      skip 'this ImageMagick does not write a TIFF of several images' unless formats.match?(/^\s*TIFF\*?\s+\S+\s+rw\+/)

      with_source('pages.tif', '-size', '1x6000', 'xc:red', '-size', '1x1', 'xc:blue') do |source|
        [{}, { 'decode' => 'jpeg-1x-v1' }].each do |opts|
          get source.thumb('1x>', opts.merge('frame' => '1.2')).url
          expect([last_response.status, last_response.headers['cache-control']]).to eq [404, 'no-store']

          get source.thumb('1x>', opts.merge('frame' => '1')).url
          expect([last_response.status, served_size]).to eq [200, '1x1']
        end
      end
    end

    it 'refuses a crop whose frames an MNG shares one canvas past the bounds for, and serves them as a TIFF or a MIFF' do
      formats = Open3.capture2(resizer.env[:convert_command].to_s, '-list', 'format').first
      skip 'this ImageMagick does not write a TIFF of several images' unless formats.match?(/^\s*TIFF\*?\s+\S+\s+rw\+/)

      with_source('strips.tif', '-size', '5001x1', 'xc:red', '-size', '1x5001', 'xc:blue') do |source|
        { 'mng' => 404, 'tiff' => 200, 'miff' => 200 }.each do |format, status|
          get source.thumb('5001x5001+0+0', 'format' => format).url

          expect(last_response.status).to eq(status), format
        end
      end
    end

    it 'serves a fill longer than an output may be before its crop, within the area' do
      with_source('tall.jpg', '-size', '600x2000', 'xc:white') do |source|
        get source.thumb('2000x1000#').url

        expect([last_response.status, served_size]).to eq [200, '2000x1000']
      end
    end

    it 'refuses a fill past the area before its crop' do
      with_source('tall.jpg', '-size', '1000x10000', 'xc:white') do |source|
        get source.thumb('2000x1000#').url

        expect(last_response.status).to eq 404
      end
    end

    it 'bounds each frame of an animation, and only the frame a job names' do
      with_source('animation.gif', '-size', '10x10', 'xc:red', '-size', '3000x3000', 'xc:blue') do |source|
        {
          source.thumb('100x100>')                  => 200,
          source.thumb('200x200%')                  => 404,
          source.thumb('200x200%', 'frame' => 0)    => 200,
          source.thumb('200x200%', 'frame' => 1)    => 404
        }.each do |job, status|
          get job.url

          expect(last_response.status).to eq(status), job.url
        end
      end
    end

    it 'refuses a resize that scales a GIF canvas past the bounds, and serves a fill that resets it, or a JPEG' do
      with_source('canvas.gif', '-size', '10x10', 'xc:red', '-repage', '6000x6000+100+100') do |source|
        {
          source.thumb('100x100>')                   => 404,
          source.thumb('20x20#')                     => 200,
          source.thumb('100x100>', 'format' => 'jpg') => 200,
          source.thumb('100x100>', 'format' => 'gif87') => 404,
          source.thumb('100x100>', 'format' => 'mng') => 404
        }.each do |job, status|
          get job.url

          expect(last_response.status).to eq(status), job.url
        end
      end
    end

    it 'refuses MNG output with an oversized canvas' do
      with_source('offset.miff', '-size', '10x10', 'xc:red', '-repage', '0x0+6000+6000') do |source|
        get source.thumb('100x100>', 'format' => 'mng').url

        expect(last_response.status).to eq 404
      end
    end

    {
      ['10x10', '1x1+60000+60000', '1x1'] => 'a square',
      ['11x10', '2x1+60000+0', 'x2']      => 'an oblong',
      ['10x10', '1x1-60000-60000', '1x1'] => 'a negatively placed'
    }.each do |(size, page, geometry), shape|
      it "refuses #{shape} canvas a shrink rounds down to nothing, which an MNG sizes from the offset, and serves it as a MIFF" do
        with_source('offset.miff', '-size', size, 'xc:red', '-repage', page) do |source|
          { 'mng' => 404, 'miff' => 200 }.each do |format, status|
            get source.thumb(geometry, 'format' => format).url

            expect(last_response.status).to eq(status), format
          end
        end
      end
    end

    it 'refuses a sequence whose MNG canvas the offsets of its frames build past the bounds, and serves it as a MIFF or its second frame' do
      with_source('frames.miff', '(', '-size', '10x10', 'xc:red', '-repage', '1x1+0+0', ')',
                  '(', '-size', '10x10', 'xc:blue', '-repage', '10x10+60000+60000', ')') do |source|
        {
          source.thumb('1x1', 'format' => 'mng')               => 404,
          source.thumb('1x1', 'format' => 'miff')              => 200,
          source.thumb('1x1', 'format' => 'mng', 'frame' => 1) => 200
        }.each do |job, status|
          get job.url

          expect(last_response.status).to eq(status), job.url
          expect(last_response.headers['cache-control']).to eq 'no-store' if status == 404
        end
      end
    end

    it 'serves a frame an offset places past the canvas the source declares, which an MNG keeps at that size' do
      with_source('offset.miff', '-size', '10x10', 'xc:red', '-repage', '100x100+6000+6000') do |source|
        get source.thumb('100x100>', 'format' => 'mng').url

        expect(last_response.status).to eq 200
      end
    end

    it 'serves a PNG whose canvas is metadata alone, at its own size' do
      with_source('canvas.png', '-size', '10x10', 'xc:red', '-repage', '6000x6000+100+100') do |source|
        get source.thumb('100x100>').url

        expect([last_response.status, served_size]).to eq [200, '10x10']
      end
    end

    it 'bounds the canvas by the format the output is written in, not the one the source is read in' do
      Dir.mktmpdir do |root|
        allow(configuration).to receive(:asset_path).and_return(root)
        gif = File.join(root, 'canvas.png')
        system(resizer.env[:convert_command].to_s, '-size', '10x10', 'xc:red', '-repage', '6000x6000+100+100', "gif:#{gif}", exception: true)

        get resizer.fetch_file(gif).thumb('100x100>').url

        expect([last_response.status, served_size]).to eq [200, '10x10']
      end
    end

    it 'refuses a resize that scales the canvas of an animated WebP past the bounds' do
      formats = Open3.capture2(resizer.env[:convert_command].to_s, '-list', 'format').first
      skip 'this ImageMagick does not write animated WebP' unless formats.match?(/^\s*WEBP\*?\s+\S+\s+rw\+/)

      with_source('canvas.webp', '-size', '10x10', 'xc:red', '-repage', '6000x6000+100+100',
                  '(', '-size', '40x40', 'xc:blue', '-repage', '6000x6000+0+0', ')') do |source|
        get source.thumb('100x100>').url

        expect(last_response.status).to eq 404
      end
    end

    it 'serves an EXIF-oriented photo resized as it shows, and an earlier URL that orients after its resize' do
      with_source('photo.jpg', '-size', '1800x1200', 'gradient:red-blue') do |source|
        ExifOrientation.write(source.path, 6)

        get resize_service.resize('/photo.jpg', '900x>', '-auto-orient')
        expect([last_response.status, served_size]).to eq [200, '900x1350']

        get source.thumb('900x>', 'decode' => 'jpeg-1x-v1').process(:convert, '-auto-orient').url
        expect([last_response.status, served_size]).to eq [200, '600x900']
      end
    end

    it 'serves a local source named with the version its host gives it' do
      with_source('photo.png', '-size', '600x300', 'xc:red') do
        get resize_service.resize('/photo.png?1183150800', '30x')

        expect([last_response.status, served_size]).to eq [200, '30x15']
      end
    end

    it 'serves the new image for a new source query, though the request carries the earlier ETag' do
      with_source('photo.png', '-size', '600x300', 'xc:red') do |source|
        service = resize_service
        get service.resize('/photo.png?1', '30x')
        etag = last_response.headers['etag']
        expect([last_response.status, etag]).to match [200, be_present]

        system(resizer.env[:convert_command].to_s, '-size', '600x600', 'xc:blue', source.path, exception: true)
        get service.resize('/photo.png?2', '30x'), {}, 'HTTP_IF_NONE_MATCH' => etag

        expect([last_response.status, served_size]).to eq [200, '30x30']
      end
    end

    it 'serves an EXIF 7 photo cropped as it shows' do
      with_source('photo.jpg', '-size', '1800x1200', 'gradient:red-blue') do |source|
        ExifOrientation.write(source.path, 7)

        get resize_service.resize('/photo.jpg', '600x200#', '-auto-orient')
        expect([last_response.status, served_size]).to eq [200, '600x200']
      end
    end

    it 'serves a transposed frame far off its canvas on a canvas of its own size' do
      with_source('long.miff', '-size', '100x1000', 'xc:red', '-repage', '1x1+500000+0', '-orient', 'LeftTop') do |source|
        get source.thumb('3000x1!', 'orient' => true, 'format' => 'mng').url

        expect([last_response.status, served_size]).to eq [200, '3000x1']
      end
    end

    it 'serves a crop of a region outside the image' do
      with_source('photo.png', '-size', '600x300', 'xc:red') do |source|
        get source.thumb('500x500+9000+9000').url

        expect(last_response.status).to eq 200
      end
    end

    it 'serves a fill that shrinks a photo, with the decode option' do
      with_source('photo.jpg', '-size', '4032x3024', 'gradient:red-blue') do |source|
        get source.thumb('2292x1125#', 'decode' => 'jpeg-1x-v1').url

        expect([last_response.status, served_size]).to eq [200, '2292x1125']
      end
    end

  end

  context 'an ImageMagick command that does not exist' do

    let(:mode) { :production }
    let(:key)  { 'a deployment key' }

    before do
      skip 'ImageMagick is not installed' unless File.exist?(resizer.env[:convert_command].to_s)
      resizer.env[:convert_command] = '/nonexistent/steam/convert'
      allow(Dragonfly).to receive(:warn)
    end

    it 'answers 500 for a new and an earlier URL' do
      [job.thumb('4x4', 'decode' => 'jpeg-1x-v1').url, job.thumb('4x4').url].each do |url|
        get url

        expect(last_response.status).to eq 500
        expect(last_response.headers['cache-control']).to eq 'no-store'
      end
      expect(Dragonfly).to have_received(:warn).with(/\Acaught error - Command failed/).twice
    end

  end

end
