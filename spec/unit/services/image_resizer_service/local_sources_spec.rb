require 'spec_helper'

describe Locomotive::Steam::ImageResizerService::LocalSources do

  let(:root)      { Dir.mktmpdir }
  let(:outside)   { Dir.mktmpdir }
  let(:rule)      { described_class.new }

  before do
    allow(Locomotive::Steam.configuration).to receive(:asset_path).and_return(root)

    FileUtils.mkdir_p(File.join(root, 'images'))
    File.write(File.join(root, 'images/banner.png'), 'png')
    File.write(File.join(outside, 'secret.txt'), 'secret')
  end

  after { FileUtils.rm_rf([root, outside]) }

  def at(path)
    File.join(root, path)
  end

  def expect_refused(path, reason)
    expect { rule.check(path) }.to raise_error(Dragonfly::Job::Fetch::NotFound, /#{Regexp.escape(reason)}/)
    expect(rule === path).to be false
  end

  it 'accepts a file inside the asset path' do
    expect(rule.check(at('images/banner.png'))).to eq File.realpath(at('images/banner.png'))
    expect(rule === at('images/banner.png')).to be true
  end

  it 'follows a link that stays inside the asset path' do
    File.symlink(at('images/banner.png'), at('images/alias.png'))

    expect(rule === at('images/alias.png')).to be true
  end

  it 'refuses a path that climbs out of the asset path' do
    expect_refused(at("../#{File.basename(outside)}/secret.txt"), 'is outside the asset path')
  end

  it 'refuses a sibling directory whose name starts like the asset path' do
    sibling = "#{root}-sibling"
    FileUtils.mkdir_p(sibling)
    File.write(File.join(sibling, 'secret.txt'), 'secret')

    expect_refused(File.join(sibling, 'secret.txt'), 'is outside the asset path')
  ensure
    FileUtils.rm_rf(sibling)
  end

  it 'refuses a link that leads out of the asset path' do
    File.symlink(File.join(outside, 'secret.txt'), at('images/secret.png'))

    expect_refused(at('images/secret.png'), 'is outside the asset path')
  end

  it 'refuses a directory' do
    expect_refused(at('images'), 'is not a file')
  end

  it 'refuses a missing file and a path holding a NUL' do
    expect_refused(at('images/missing.png'), 'is not found')
    expect_refused("#{at('images/banner.png')}\0.png", 'is not found')
  end

  describe '#path_for' do

    it 'joins a source to the asset path and checks it' do
      expect(rule.path_for('/images/banner.png')).to eq File.join(root, '/images/banner.png')
      expect { rule.path_for('/images/missing.png') }.to raise_error(Dragonfly::Job::Fetch::NotFound, /is not found/)
      expect { rule.path_for("/images/banner.png\0.png") }.to raise_error(Dragonfly::Job::Fetch::NotFound, /is not found/)
    end

  end

  context 'without an asset path' do

    before { allow(Locomotive::Steam.configuration).to receive(:asset_path).and_return(nil) }

    it { expect_refused(at('images/banner.png'), 'no asset path') }

  end

end
