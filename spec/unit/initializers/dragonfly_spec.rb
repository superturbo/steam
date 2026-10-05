require 'spec_helper'

describe Locomotive::Steam::Initializers::Dragonfly do

  let(:initializer) { Locomotive::Steam::Initializers::Dragonfly.new }

  subject { ::Dragonfly.app(:steam).plugins[:imagemagick] }

  describe 'with ImagickMagick' do

    before { initializer.run }
    it { is_expected.not_to eq nil }

    it 'resizes with the Steam thumb processor' do
      expect(::Dragonfly.app(:steam).get_processor(:thumb)).to be_a(Locomotive::Steam::ImageResizerService::Thumb)
    end

  end

  describe 'ImageMagick without identify' do

    let(:convert) { Tempfile.new('convert') }

    around do |example|
      kept = ENV.values_at('IMAGE_MAGICK_CONVERT', 'IMAGE_MAGICK_IDENTIFY')
      example.run
    ensure
      ENV['IMAGE_MAGICK_CONVERT'], ENV['IMAGE_MAGICK_IDENTIFY'] = kept
      initializer.run
    end

    it 'refuses to start' do
      ENV['IMAGE_MAGICK_CONVERT']  = convert.path
      ENV['IMAGE_MAGICK_IDENTIFY'] = '/nonexistent/steam/identify'

      expect { initializer.run }.to raise_error(RuntimeError, %r{identify.*/nonexistent/steam/identify})
    end

  end

  describe 'missing ImagickMagick' do

    before do
      ::Dragonfly::App.destroy_apps
      expect(File).to receive(:exist?).and_return(false)
      initializer.run
    end
    it { is_expected.to eq nil }

    after(:all) do
      Locomotive::Steam::Initializers::Dragonfly.new.run
    end

  end

  describe 'the key resize URLs are signed with' do

    let(:configuration) { Locomotive::Steam.configuration }
    let(:mode)          { :production }
    let(:key)           { nil }

    subject { initializer.run; ::Dragonfly.app(:steam).secret }

    # The Dragonfly key is global: restore the suite's key once the stubs are gone.
    around do |example|
      example.run
      initializer.run
    end

    before { allow(configuration).to receive_messages(mode: mode, image_resizer_secret: key) }

    context 'a configured key' do

      let(:key) { 'a deployment key' }
      it { is_expected.to eq 'a deployment key' }

    end

    [nil, '', '  ', 'please change it'].each do |value|

      context "#{value.inspect} outside test mode" do

        let(:key) { value }

        it 'refuses to start' do
          expect { initializer.run }.to raise_error(ArgumentError, /image_resizer_secret/)
        end

      end

    end

    [1, :a_key].each do |value|

      [:production, :test].each do |mode_name|

        context "#{value.inspect} in #{mode_name} mode" do

          let(:mode) { mode_name }
          let(:key)  { value }

          it 'refuses to start' do
            expect { initializer.run }.to raise_error(ArgumentError, /image_resizer_secret/)
          end

        end

      end

    end

    context 'no key in test mode' do

      let(:mode) { :test }

      it 'signs with a key generated at initialization' do
        is_expected.to match(/\A\h{64}\z/)
        expect { initializer.run }.to change { ::Dragonfly.app(:steam).secret }
      end

    end

    context 'the public placeholder in test mode' do

      let(:mode) { :test }
      let(:key)  { 'please change it' }

      it { is_expected.to match(/\A\h{64}\z/) }

    end

    context 'a configured key in test mode' do

      let(:mode) { :test }
      let(:key)  { 'a deployment key' }

      it { is_expected.to eq 'a deployment key' }

    end

  end

  describe 'the trusted remote resize source prefix' do

    let(:configuration) { Locomotive::Steam.configuration }

    [nil, 'https://cdn.example.com/sites/', 'http://bucket.s3.amazonaws.com'].each do |value|
      it "starts with #{value.inspect}" do
        allow(configuration).to receive(:image_resizer_remote_source_prefix).and_return(value)

        expect { initializer.run }.not_to raise_error
      end
    end

    [
      ['https://cdn.example.com/sites/'], 'ftp://cdn.example.com/', 'cdn.example.com/sites/', 'https:///sites/',
      'https://user:secret@cdn.example.com/', 'https://cdn.example.com/?a=1', 'https://cdn.example.com/#top',
      'https://cdn example.com/', '', 1
    ].each do |value|
      it "refuses to start with #{value.inspect}" do
        allow(configuration).to receive(:image_resizer_remote_source_prefix).and_return(value)

        expect { initializer.run }.to raise_error(ArgumentError, /image_resizer_remote_source_prefix/)
      end
    end

  end

  describe 'fetch_url jobs' do

    let(:app) { ::Dragonfly.app(:steam) }

    it 'serves none, whatever an earlier configuration allowed' do
      app.configure { fetch_url_whitelist [/.+/] }
      initializer.run

      status, _headers, _body = app.call(Rack::MockRequest.env_for(app.fetch_url('http://cdn.example.com/a.png').url))

      expect(status).to eq 403
    end

  end

  describe 'fetch_file jobs' do

    let(:app)   { ::Dragonfly.app(:steam) }
    let(:image) { File.expand_path('../../fixtures/default/public/images/nav_on.png', __dir__) }

    it 'serves none outside the asset path, whatever an earlier configuration allowed' do
      Dir.mktmpdir do |root|
        allow(Locomotive::Steam.configuration).to receive(:asset_path).and_return(root)
        app.configure { fetch_file_whitelist [/public/] }
        initializer.run

        status, _headers, _body = app.call(Rack::MockRequest.env_for(app.fetch_file(image).url))

        expect(status).to eq 403
      end
    end

  end

end
