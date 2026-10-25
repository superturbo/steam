require 'spec_helper'

describe Locomotive::Steam::Configuration do

  subject { Locomotive::Steam::Configuration.new }

  describe 'default values' do

    it { expect(subject.mode).to eq(:production) }
    it { expect(subject.serve_assets).to eq(true) }
    it { expect(subject.asset_path).to eq(nil) }
    it { expect(subject.log_level).to eq(::Logger::INFO) }

  end

  describe 'the trusted remote resize source prefix' do

    it { expect(subject.image_resizer_remote_source_prefix).to eq nil }

    it 'takes a URL prefix' do
      subject.image_resizer_remote_source_prefix = 'https://cdn.example.com/sites/'
      expect(subject.image_resizer_remote_source_prefix).to eq 'https://cdn.example.com/sites/'
    end

  end

  describe 'the resize bounds' do

    it 'bound an output at 5760 px a side and 25,000,000 pixels' do
      expect([subject.image_resizer_max_side, subject.image_resizer_max_area]).to eq [5760, 25_000_000]
    end

  end

  describe 'the ImageMagick command slots' do

    it 'let five commands run at once, two of them for one site, each waiting up to ten seconds for its slots' do
      expect([subject.image_magick_max_concurrent_commands, subject.image_magick_max_concurrent_commands_per_site,
              subject.image_magick_command_queue_timeout]).to eq [5, 2, 10]
    end

    it 'keep their files in the system temporary directory, apart for each user' do
      expect(subject.image_magick_command_lock_path).to eq File.join(Dir.tmpdir, "steam-image-magick-#{Process.euid}")
    end

  end

  describe 'assign a different value' do

    before { subject.mode = :test }
    it { expect(subject.mode).to eq(:test) }
    it { expect(subject.log_level).to eq(::Logger::INFO) }

    context 'a log level set by the host' do

      before { subject.log_level = ::Logger::DEBUG }
      it { expect(subject.log_level).to eq(::Logger::DEBUG) }

    end

    context 'the initial value was true' do

      before { subject.serve_assets = false }
      it { expect(subject.serve_assets).to eq(false) }

    end

  end

  describe 'the logger Locomotive::Steam.configure builds' do

    after do
      Locomotive::Steam.configuration.log_level = nil
      Locomotive::Steam.configuration.log_file  = nil
      reset_logger
    end

    it 'logs at the info level unless the host sets one' do
      Locomotive::Steam.configure { |config| config.log_level = nil }

      expect(Locomotive::Common::Logger.instance.logger.level).to eq(::Logger::INFO)
    end

    it 'logs at the level the host sets' do
      Locomotive::Steam.configure { |config| config.log_level = ::Logger::DEBUG }

      expect(Locomotive::Common::Logger.instance.logger.level).to eq(::Logger::DEBUG)
    end

    it 'refuses a blank or unknown log level' do
      ['', '   ', 'verbose'].each do |level|
        expect { Locomotive::Steam.configure { |config| config.log_level = level } }
          .to raise_error(ArgumentError, /invalid log level/)
      end
    end

    it 'writes to the standard output without a log file' do
      expect {
        Locomotive::Steam.configure { |config| config.log_file = nil }
        Locomotive::Common::Logger.info 'a line for the standard output'
      }.to output(/a line for the standard output/).to_stdout
    end

  end

end
