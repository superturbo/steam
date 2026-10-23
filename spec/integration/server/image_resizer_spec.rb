require File.dirname(__FILE__) + '/../integration_helper'

describe 'Resize jobs' do

  include Rack::Test::Methods

  let(:configuration) { Locomotive::Steam.configuration }
  let(:resizer)       { ::Dragonfly.app(:steam) }
  let(:image)         { File.join(default_fixture_site_path, 'public/images/nav_on.png') }
  let(:job)           { resizer.fetch_file(image) }

  def app
    run_server
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

      url = Locomotive::Steam::ImageResizerService.new(resizer).resize("http://127.0.0.1:#{port}/sites/1/banner.png", '4x4')
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

          url = Locomotive::Steam::ImageResizerService.new(resizer).resize('/current.png', '4x4')
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
