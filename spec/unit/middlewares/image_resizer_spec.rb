require 'spec_helper'

require_relative '../../../lib/locomotive/steam/middlewares/image_resizer'

describe Locomotive::Steam::Middlewares::ImageResizer do

  let(:app)        { ->(env) { [404, { 'content-type' => 'text/html' }, ['page not found']] } }
  let(:middleware) { described_class.new(app) }

  it 'leaves a request that is not a resize job to the app, with its answer' do
    status, headers, body = middleware.call(Rack::MockRequest.env_for('/about-us'))

    expect(status).to eq 404
    expect(headers).to eq('content-type' => 'text/html')
    expect(body).to eq ['page not found']
  end

  it 'leaves a request to the app whatever the case of the header that passes it on' do
    allow(::Dragonfly.app(:steam)).to receive(:call).and_return([404, { 'X-Cascade' => 'pass' }, ['Not found']])

    expect(middleware.call(Rack::MockRequest.env_for('/about-us')).last).to eq ['page not found']
  end

  describe 'the rendering site of a job' do

    let(:resizer) { ::Dragonfly.app(:steam) }
    let(:image)   { File.expand_path('../../fixtures/default/public/images/nav_on.png', __dir__) }
    let(:shell)   { Locomotive::Steam::ImageResizerService::Shell }

    def site_during(path, answer = [200, {}, ['ok']])
      seen = :none
      allow(resizer).to receive(:call) { seen = shell.site; answer }
      middleware.call(Rack::MockRequest.env_for(path))
      seen
    end

    def job_url(options)
      resizer.fetch_file(image).thumb('4x4', options).url
    end

    it 'gives the commands of a job the site it names, and none once the job is done' do
      expect(site_during(job_url('decode' => 'jpeg-1x-v1', 'site' => 'acme'))).to eq 'acme'
      expect(shell.site).to be_nil
    end

    it 'gives no site for a job that names none, or for a path that is no job' do
      expect(site_during(job_url('decode' => 'jpeg-1x-v1'))).to be_nil
      expect(site_during('/steam/dynamic/not-a-job/x/y.png')).to be_nil
    end

    it 'leaves no site to the app it passes a request on to' do
      seen_by_app = :none
      app         = ->(env) { seen_by_app = shell.site; [404, {}, []] }
      allow(resizer).to receive(:call).and_return([404, { 'x-cascade' => 'pass' }, []])

      described_class.new(app).call(Rack::MockRequest.env_for(job_url('site' => 'acme')))

      expect(seen_by_app).to be_nil
    end

    it 'restores the site it found once the job fails' do
      allow(resizer).to receive(:call).and_raise('stop')

      shell.with_site('outer') do
        expect { middleware.call(Rack::MockRequest.env_for(job_url('site' => 'acme'))) }.to raise_error('stop')
        expect(shell.site).to eq 'outer'
      end
    end

  end

  describe 'a command whose slots cannot be used' do

    let(:unavailable) { Locomotive::Steam::ImageResizerService::CommandSlots::Unavailable }

    before do
      allow(::Dragonfly.app(:steam)).to receive(:call)
        .and_raise(unavailable, 'ImageMagick command slots are unavailable: Steam cannot open /locks/command-0')
    end

    it 'answers 503 kept out of every cache, with no time to retry, and tells the operator why' do
      expect(Locomotive::Common::Logger).to receive(:error).with(/command slots are unavailable.*\/locks\/command-0/)

      status, headers, body = middleware.call(Rack::MockRequest.env_for('/steam/dynamic/job/sha/photo.png'))

      expect([status, headers['cache-control'], headers.key?('retry-after'), body.join]).to eq [503, 'no-store', false, 'Unavailable']
    end

    it 'answers a HEAD request with no body' do
      allow(Locomotive::Common::Logger).to receive(:error)

      status, _headers, body = middleware.call(Rack::MockRequest.env_for('/steam/dynamic/job/sha/photo.png', method: 'HEAD'))

      expect([status, body]).to eq [503, []]
    end

  end

  describe 'a command that finds no slot' do

    before do
      allow(::Dragonfly.app(:steam)).to receive(:call)
        .and_raise(Locomotive::Steam::ImageResizerService::CommandSlots::Busy, 'ImageMagick commands are running in every slot')
      allow(Locomotive::Steam.configuration).to receive(:image_magick_command_queue_timeout).and_return(1.5)
    end

    it 'answers 503 to retry after whole seconds, kept out of every cache' do
      status, headers, body = middleware.call(Rack::MockRequest.env_for('/steam/dynamic/job/sha/photo.png'))

      expect([status, headers['retry-after'], headers['cache-control'], body.join]).to eq [503, '2', 'no-store', 'Busy']
    end

    it 'answers a HEAD request with no body' do
      status, _headers, body = middleware.call(Rack::MockRequest.env_for('/steam/dynamic/job/sha/photo.png', method: 'HEAD'))

      expect([status, body]).to eq [503, []]
    end

  end

end
