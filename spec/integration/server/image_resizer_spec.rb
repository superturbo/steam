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

      head url_signed_with('please change it')
      expect(last_response.status).to eq 400
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

    it 'answers 500 for a new and an earlier URL, and logs no command' do
      [job.thumb('4x4', 'decode' => 'jpeg-1x-v1').url, job.thumb('4x4').url].each do |url|
        get url

        expect(last_response.status).to eq 500
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
      end
      expect(Dragonfly).to have_received(:warn).with(/\Acaught error - Command failed/).twice
    end

  end

end
