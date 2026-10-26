require 'spec_helper'
require 'open3'

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

      expect { initializer.run }.to raise_error(RuntimeError, %r{ImageMagick's identify, which is not found: /nonexistent/steam/identify})
    end

  end

  describe 'the ImageMagick commands it finds' do

    let(:magick)   { Tempfile.new('magick') }
    let(:convert)  { Tempfile.new('convert') }
    let(:identify) { Tempfile.new('identify') }

    around do |example|
      kept = ENV.values_at('IMAGE_MAGICK_CONVERT', 'IMAGE_MAGICK_IDENTIFY')
      example.run
    ensure
      ENV['IMAGE_MAGICK_CONVERT'], ENV['IMAGE_MAGICK_IDENTIFY'] = kept
      initializer.run
    end

    before do
      ENV.delete('IMAGE_MAGICK_CONVERT')
      ENV['IMAGE_MAGICK_IDENTIFY'] = identify.path
      allow_any_instance_of(Locomotive::Steam::ImageResizerService::Shell).to receive(:check_policy)
      allow(initializer).to receive(:`).and_call_original
    end

    def converting_with(magick: nil, convert: nil)
      allow(initializer).to receive(:`).with('which magick').and_return("#{magick}\n")
      allow(initializer).to receive(:`).with('which convert').and_return("#{convert}\n")
      initializer.run
      ::Dragonfly.app(:steam).env[:convert_command]
    end

    it "converts with ImageMagick 7's magick, not the convert command it deprecates" do
      expect(converting_with(magick: magick.path, convert: convert.path)).to eq magick.path
    end

    it 'converts with convert where there is no magick, as with ImageMagick 6' do
      expect(converting_with(convert: convert.path)).to eq convert.path
    end

    it 'converts with the command the host names' do
      ENV['IMAGE_MAGICK_CONVERT'] = convert.path

      expect(converting_with(magick: magick.path)).to eq convert.path
    end

  end

  describe 'missing ImagickMagick' do

    before do
      ::Dragonfly::App.destroy_apps
      expect(File).to receive(:exist?).and_return(false)
      initializer.run
    end
    it { is_expected.to eq nil }

    it "keeps Dragonfly's shell" do
      expect(::Dragonfly.app(:steam).shell).to be_instance_of(::Dragonfly::Shell)
    end

    it 'runs no ImageMagick command for a :convert job' do
      app = ::Dragonfly.app(:steam)
      allow(app.shell).to receive(:run)

      expect { app.new_job('image').process(:convert, '-quality 70').apply }
        .to raise_error(::Dragonfly::Register::NotFound)
      expect(app.shell).not_to have_received(:run)
    end

    after(:all) do
      Locomotive::Steam::Initializers::Dragonfly.new.run
    end

  end

  describe 'missing ImageMagick on a platform without process groups' do

    before do
      ::Dragonfly::App.destroy_apps
      allow(File).to receive(:exist?).and_return(false)
      allow(Gem).to receive(:win_platform?).and_return(true)
    end

    after(:all) do
      Locomotive::Steam::Initializers::Dragonfly.new.run
    end

    it 'starts with resizing disabled' do
      expect { initializer.run }.not_to raise_error
      expect(::Dragonfly.app(:steam).plugins[:imagemagick]).to be_nil
    end

  end

  describe 'the ImageMagick commands of resize jobs' do

    let(:app)           { ::Dragonfly.app(:steam) }
    let(:configuration) { Locomotive::Steam.configuration }

    around do |example|
      example.run
      initializer.run
    end

    it 'run through a shell with a 30 s timeout per command' do
      initializer.run

      expect(app.shell).to be_a(Locomotive::Steam::ImageResizerService::Shell)
      expect(app.shell.timeout).to eq 30
    end

    it 'take the timeout from the configuration' do
      allow(configuration).to receive(:image_magick_command_timeout).and_return(12)
      initializer.run

      expect(app.shell.timeout).to eq 12
    end

    %i(image_resizer_max_side image_resizer_max_area).product([0, -1, 1.5, '5760']).each do |name, value|
      it "refuse to start with #{name} of #{value.inspect}" do
        allow(configuration).to receive(name).and_return(value)

        expect { initializer.run }.to raise_error(ArgumentError, /#{name}/)
      end
    end

    %i(image_resizer_max_side image_resizer_max_area).each do |name|
      it "refuse to start with #{name} set to false" do
        configuration.public_send(:"#{name}=", false)

        expect { initializer.run }.to raise_error(ArgumentError, /#{name}/)
      ensure
        configuration.public_send(:"#{name}=", nil)
      end
    end

    [0, -1, Float::INFINITY, Float::NAN, Complex(1, 1), '30'].each do |value|
      it "refuse to start with a timeout of #{value.inspect}" do
        allow(configuration).to receive(:image_magick_command_timeout).and_return(value)

        expect { initializer.run }.to raise_error(ArgumentError, /image_magick_command_timeout/)
      end
    end

    describe 'with ImageMagick' do

      let(:image) { File.expand_path('../../fixtures/default/public/images/nav_on.png', __dir__) }

      before do
        initializer.run
        skip 'ImageMagick is not installed' unless File.exist?(app.env[:convert_command].to_s)
        allow(app.shell).to receive(:run).and_call_original
      end

      it 'refuse to start when the check of the ImageMagick policy fails' do
        allow_any_instance_of(Locomotive::Steam::ImageResizerService::Shell).to receive(:check_policy)
          .with(convert: app.env[:convert_command], identify: app.env[:identify_command])
          .and_raise(RuntimeError, 'check failed')

        expect { initializer.run }.to raise_error(RuntimeError, 'check failed')
      end

      it 'all go through that shell, for new and earlier URLs' do
        app.fetch_file(image).thumb('4x4', 'decode' => 'jpeg-1x-v1').process(:convert, '-quality 70').apply
        app.fetch_file(image).thumb('4x4').apply
        app.fetch_file(image).width

        expect(app.shell).to have_received(:run).with(/identify/, anything).exactly(3).times
        expect(app.shell).to have_received(:run).with(/\A#{Regexp.escape(app.env[:convert_command])} /, anything).exactly(3).times
      end

    end

  end

  describe 'the ImageMagick command slots' do

    let(:configuration) { Locomotive::Steam.configuration }
    let(:app)           { ::Dragonfly.app(:steam) }
    let(:locks)         { File.join(Dir.mktmpdir, 'locks') }
    let(:image)         { File.expand_path('../../fixtures/default/public/images/nav_on.png', __dir__) }

    # The Dragonfly shell is global: restore the suite's slots once the stubs are gone.
    around do |example|
      example.run
      initializer.run
      FileUtils.rm_rf(File.dirname(locks))
    end

    before { allow(configuration).to receive(:image_magick_command_lock_path).and_return(locks) }

    it 'makes a lock directory only its user can use' do
      initializer.run

      expect(File.stat(locks).mode & 0o777).to eq 0o700 if File.exist?(app.env[:convert_command].to_s)
    end

    it 'runs a job only in a free slot' do
      allow(configuration).to receive_messages(image_magick_max_concurrent_commands: 1, image_magick_max_concurrent_commands_per_site: 1,
                                               image_magick_command_queue_timeout: 0)
      initializer.run
      skip 'ImageMagick is not installed' unless File.exist?(app.env[:convert_command].to_s)
      slots = Locomotive::Steam::ImageResizerService::CommandSlots.new(directory: locks, total: 1, per_site: 1, wait: 0)

      slots.hold(nil) do
        expect { app.fetch_file(image).thumb('4x4', 'decode' => 'jpeg-1x-v1').apply }
          .to raise_error(Locomotive::Steam::ImageResizerService::CommandSlots::Busy)
      end
    end

    [0, -1, 1.5, '1'].each do |value|
      it "refuses to start with image_magick_max_concurrent_commands of #{value.inspect}" do
        allow(configuration).to receive(:image_magick_max_concurrent_commands).and_return(value)

        expect { initializer.run }.to raise_error(ArgumentError, /image_magick_max_concurrent_commands /)
      end
    end

    [0, 2, 1.5, '1'].each do |value|
      it "refuses to start with image_magick_max_concurrent_commands_per_site of #{value.inspect} for 1 command" do
        allow(configuration).to receive_messages(image_magick_max_concurrent_commands: 1, image_magick_max_concurrent_commands_per_site: value)

        expect { initializer.run }.to raise_error(ArgumentError, /image_magick_max_concurrent_commands_per_site/)
      end
    end

    [-1, Float::INFINITY, Float::NAN, Complex(1, 1), '1'].each do |value|
      it "refuses to start with image_magick_command_queue_timeout of #{value.inspect}" do
        allow(configuration).to receive(:image_magick_command_queue_timeout).and_return(value)

        expect { initializer.run }.to raise_error(ArgumentError, /image_magick_command_queue_timeout/)
      end
    end

    it 'refuses to start with a lock directory others can use, or a link to one' do
      skip 'ImageMagick is not installed' unless File.exist?(app.env[:convert_command].to_s)
      FileUtils.mkdir_p(locks)
      File.chmod(0o777, locks)
      expect { initializer.run }.to raise_error(ArgumentError, /image_magick_command_lock_path/)

      link = "#{locks}-link"
      File.chmod(0o700, locks)
      File.symlink(locks, link)
      allow(configuration).to receive(:image_magick_command_lock_path).and_return(link)
      expect { initializer.run }.to raise_error(ArgumentError, /image_magick_command_lock_path/)
    end

  end

  describe 'the log of the start-up checks' do

    it "goes through Steam's logger from a new process on, leaving no dragonfly.log behind" do
      skip 'ImageMagick is not installed' unless File.exist?(::Dragonfly.app(:steam).env[:convert_command].to_s)
      steam = File.expand_path('../../../lib/locomotive/steam', __dir__)

      Dir.mktmpdir do |dir|
        script = <<~RUBY
          require #{steam.inspect}
          Locomotive::Steam.configure do |config|
            config.mode                           = :test
            config.log_level                      = ::Logger::DEBUG
            config.image_magick_command_lock_path = File.join(Dir.pwd, 'locks')
          end
        RUBY
        output, status = Open3.capture2e(RbConfig.ruby, '-e', script, chdir: dir)

        expect(status).to be_success, output
        expect(output).to include('DRAGONFLY: shell command')
        expect(Dir.children(dir)).not_to include('dragonfly.log')
      end
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
