require 'spec_helper'

describe Locomotive::Steam::ImageResizerService do

  let(:resizer) { nil }
  let(:service) { described_class.new(resizer) }
  let(:public)  { File.expand_path('../../fixtures/default/public', __dir__) }

  before { allow(Locomotive::Steam.configuration).to receive(:asset_path).and_return(public) }

  describe '#resize' do

    let(:geometry)  { '400x30#' }
    let(:input)     { 'http://upload.wikimedia.org/wikipedia/en/thumb/b/b5/Metropolitan_railway_steam_locomotive_2781022036.png/240px-Metropolitan_railway_steam_locomotive_2781022036.png' }

    subject { service.resize(input, geometry) }

    describe 'no resizer' do
      it { is_expected.to eq 'http://upload.wikimedia.org/wikipedia/en/thumb/b/b5/Metropolitan_railway_steam_locomotive_2781022036.png/240px-Metropolitan_railway_steam_locomotive_2781022036.png' }
    end

    describe 'DragonFly' do

      let(:resizer) { Dragonfly.app(:steam) }

      before { allow(Locomotive::Steam.configuration).to receive(:image_resizer_remote_source_prefix).and_return('http://upload.wikimedia.org/wikipedia/') }

      describe 'a source with no URL or path' do

        let(:input) { { 'filename' => 'private-name.png' } }

        it 'names the source it could not resize' do
          logged = []
          allow(Locomotive::Common::Logger).to receive(:error) { |message| logged << message }

          expect(subject).to be_nil
          expect(logged.join).to include('Unable to resize on the fly', 'private-name.png')
        end

      end

      it 'keeps the URL of a trusted remote image in the job' do
        job   = subject[%r{/steam/dynamic/([^/]+)/}, 1]
        steps = JSON.parse(Base64.urlsafe_decode64(job + '=' * (-job.size % 4)))

        expect(steps.first).to eq ['fu', input]
      end

      it 'keeps the query of a remote image in its URL alone' do
        url   = "#{input}?1183150800"
        steps = ::Dragonfly::Job.deserialize(service.resize(url, geometry).split('/')[3], resizer).steps

        expect([steps.first.args, steps.last.args]).to eq [[url], ['thumb', geometry, { 'decode' => 'jpeg-1x-v1' }]]
      end

      describe 'a remote image outside the trusted sources' do

        let(:input) { 'http://169.254.169.254/latest/meta-data/banner.png' }

        it 'signs nothing and logs why' do
          expect(Locomotive::Common::Logger).to receive(:error).with(/is not from a trusted resize source/)
          is_expected.to eq nil
        end

      end

      describe 'no imagemagick' do
        before { expect(resizer.plugins).to receive(:[]).with(:imagemagick).and_return(nil) }
        it { is_expected.to eq 'http://upload.wikimedia.org/wikipedia/en/thumb/b/b5/Metropolitan_railway_steam_locomotive_2781022036.png/240px-Metropolitan_railway_steam_locomotive_2781022036.png' }
      end

      describe 'no geometry' do
        let(:geometry) { '' }
        it { is_expected.to eq 'http://upload.wikimedia.org/wikipedia/en/thumb/b/b5/Metropolitan_railway_steam_locomotive_2781022036.png/240px-Metropolitan_railway_steam_locomotive_2781022036.png' }
      end

      it { is_expected.to match /\/steam\/dynamic\/.*\/240px-Metropolitan_railway_steam_locomotive_2781022036.png/ }

      describe 'a local asset' do

        let(:input)  { '/images/nav_on.png' }
        it { is_expected.to match /\/steam\/dynamic\/.*\/nav_on.png/ }

        it 'signs a versioned thumb job under a new URL' do
          job   = subject[%r{/steam/dynamic/([^/]+)/}, 1]
          steps = JSON.parse(Base64.urlsafe_decode64(job + '=' * (-job.size % 4)))
          file  = resizer.fetch_file(File.join(public, '/images/nav_on.png'))

          expect(steps.last).to eq ['p', 'thumb', geometry, { 'decode' => 'jpeg-1x-v1' }]
          expect(subject).to eq file.thumb(geometry, 'decode' => 'jpeg-1x-v1').url
          expect(subject).not_to eq file.thumb(geometry).url
        end

      end

      describe 'a local path holding a NUL' do

        let(:input) { "/images/nav_on.png\0.png" }

        it 'signs nothing and logs why' do
          expect(Locomotive::Common::Logger).to receive(:error).with(/is not found/)
          is_expected.to eq nil
        end

      end

      describe 'a local file outside the asset path' do

        let(:input) { '/../config/site.yml' }

        it 'signs nothing and logs why' do
          expect(Locomotive::Common::Logger).to receive(:error).with(/is outside the asset path/)
          is_expected.to eq nil
        end

      end

      describe 'a hash' do

        let(:input) { { 'url' => '/images/nav_on.png' } }
        it { is_expected.to match /\/steam\/dynamic\/.*\/nav_on.png/ }

      end

      describe 'an object responding to the url method (Carrierwave uploaded file)' do

        let(:input)  { instance_double('UploadedFile', url: '/images/photo_frame.png') }
        it { is_expected.to match /\/steam\/dynamic\/.*\/photo_frame.png/ }

      end

      describe 'a local source with a query' do

        let(:input)  { '/images/nav_on.png?24e29997bcb00e97d8252cdd29d14e2d' }
        it { is_expected.to match /\/steam\/dynamic\/.*\/[a-z0-9]+\/nav_on.png/ }

        it 'keeps the version its query gives in the job, and reads the file without it' do
          steps = ::Dragonfly::Job.deserialize(subject.split('/')[3], resizer).steps

          expect([steps.first.args, steps.last.args]).to eq [
            [File.join(public, '/images/nav_on.png')],
            ['thumb', geometry, { 'decode' => 'jpeg-1x-v1', 'version' => '24e29997bcb00e97d8252cdd29d14e2d' }]
          ]
        end

        it 'changes the resize URL when the source query changes' do
          expect(service.resize('/images/nav_on.png?1', geometry)).to eq service.resize('/images/nav_on.png?1', geometry)
          expect(service.resize('/images/nav_on.png?1', geometry)).not_to eq service.resize('/images/nav_on.png?2', geometry)
        end

        it 'reads an empty query as no version' do
          expect(service.resize('/images/nav_on.png?', geometry)).to eq service.resize('/images/nav_on.png', geometry)
        end

        it 'keeps the version next to the orient option' do
          steps = ::Dragonfly::Job.deserialize(service.resize(input, geometry, '-auto-orient').split('/')[3], resizer).steps

          expect(steps.last.args.last).to eq('decode' => 'jpeg-1x-v1', 'orient' => true, 'version' => '24e29997bcb00e97d8252cdd29d14e2d')
        end

      end

      describe 'unable to fetch a file' do

        before { allow(service).to receive(:fetch_file).and_return(nil) }
        it { is_expected.to eq nil }

      end

      describe 'nil file' do
        let(:geometry) { '' }
        let(:input)  { nil }

        it { is_expected.to eq nil }
      end

      describe 'nil hash file' do
        let(:input) { { 'url' => nil } }

        it { is_expected.to eq nil }
      end

      describe 'nil object file' do
        let(:input)  { instance_double('UploadedFile', url: nil) }

        it { is_expected.to eq nil }
      end

      describe 'ImageMagick arguments' do
        let(:input) { '/images/nav_on.png' }

        it 'signs a job with the arguments the resize options produce' do
          expect(service.resize(input, geometry, '-quality 70 -auto-orient')).to match(/\/steam\/dynamic\/.*\/nav_on.png/)
        end

        it 'signs no job, and logs why, for other arguments' do
          logged = []
          allow(Locomotive::Common::Logger).to receive(:error) { |message| logged << message }

          expect(service.resize(input, geometry, '-quality 70 -write /tmp/copy.png')).to be_nil
          expect(logged.join).to include('Unable to resize on the fly', 'ImageMagick arguments')
          expect(logged.join).not_to include('/tmp/copy.png')
        end
      end

      describe 'the auto-orient argument' do
        let(:input) { '/images/nav_on.png' }

        def steps(url)
          job = ::Dragonfly::Job.deserialize(url.split('/')[3], resizer)
          job.steps.grep(::Dragonfly::Job::Process).map(&:args)
        end

        it 'orients the image in the resize, before its geometry, not after it' do
          expect(steps(service.resize(input, '30x40#', '-quality 70 -auto-orient')))
            .to eq [['thumb', '30x40#', { 'decode' => 'jpeg-1x-v1', 'orient' => true }], ['convert', '-quality 70']]
          expect(steps(service.resize(input, '30x40#', '-auto-orient')))
            .to eq [['thumb', '30x40#', { 'decode' => 'jpeg-1x-v1', 'orient' => true }]]
        end

        it 'leaves other ImageMagick arguments as they are' do
          expect(steps(service.resize(input, '30x40#', '-quality 70 -strip')))
            .to eq [['thumb', '30x40#', { 'decode' => 'jpeg-1x-v1' }], ['convert', '-quality 70 -strip']]
        end
      end

      describe 'a geometry Steam does not run' do
        let(:input) { '/images/nav_on.png' }

        it 'signs no job, and logs why' do
          logged = []
          allow(Locomotive::Common::Logger).to receive(:error) { |message| logged << message }
          expect(resizer).not_to receive(:fetch_file)

          expect(service.resize(input, '40x30#xx')).to be_nil
          expect(logged).to eq ['Unable to resize on the fly: Steam does not run this geometry']
        end
      end

    end

  end

end
