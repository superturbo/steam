require 'spec_helper'

describe Locomotive::Steam::ImageResizerService::RemoteSources do

  let(:prefix)  { 'http://cdn.example.com/sites/' }
  let(:rule)    { described_class.new }

  before { allow(Locomotive::Steam.configuration).to receive(:image_resizer_remote_source_prefix).and_return(prefix) }

  it 'accepts a URL under a trusted source' do
    expect { rule.check('http://cdn.example.com/sites/1/banner.png?123') }.not_to raise_error
    expect { rule.check('http://CDN.example.com/sites/1/banner.png') }.not_to raise_error
    expect(rule === 'http://cdn.example.com/sites/1/banner.png').to be true
  end

  [
    'http://other.example.com/sites/1/banner.png',
    'http://cdn.example.com.evil.com/sites/1/banner.png',
    'http://cdn.example.com/other/banner.png',
    'http://cdn.example.com/sites-x/banner.png',
    'https://cdn.example.com/sites/1/banner.png',
    'https://cdn.example.com:80/sites/1/banner.png',
    'http://cdn.example.com:8080/sites/1/banner.png',
    'http://user:secret@cdn.example.com/sites/1/banner.png',
    'http://cdn.example.com/sites/../other/banner.png',
    'http://cdn.example.com/sites/./1/banner.png',
    'http://cdn.example.com/sites/%2e%2e/other/banner.png',
    'http://cdn.example.com/sites/..%2fother/banner.png',
    'http://cdn.example.com/sites/1%5c..%5cbanner.png',
    'data:image/png;base64,iVBORw0KGgo=',
    'ftp://cdn.example.com/sites/1/banner.png',
    'http://cdn.example.com/sites/1/ban ner.png'
  ].each do |url|
    it "refuses #{url}" do
      expect { rule.check(url) }.to raise_error(Dragonfly::Job::Fetch::NotFound)
      expect(rule === url).to be false
    end
  end

  it 'names neither a user nor a query when it refuses a URL' do
    [
      'http://user:secret@cdn.example.com/sites/1/banner.png?token=hidden',
      'http://other.example.com/sites/1/banner.png?token=hidden',
      'http://cdn.example.com/sites/1/ban ner.png?token=hidden'
    ].each do |url|
      expect { rule.check(url) }.to raise_error(Dragonfly::Job::Fetch::NotFound) { |error|
        expect(error.message).not_to include('secret')
        expect(error.message).not_to include('hidden')
      }
    end
  end

  it 'names the host and path of a URL it refuses' do
    expect { rule.check('http://other.example.com/sites/1/banner.png?token=hidden') }.to raise_error(
      Dragonfly::Job::Fetch::NotFound, %r{other\.example\.com/sites/1/banner\.png"})
  end

  context 'with a prefix written without its closing slash' do

    let(:prefix) { 'http://cdn.example.com/sites' }

    it 'keeps to the directory it names' do
      expect(rule === 'http://cdn.example.com/sites/1/banner.png').to be true
      expect(rule === 'http://cdn.example.com/sites-x/banner.png').to be false
    end

  end

  context 'with a value that is not a URL prefix, set after start' do

    let(:prefix) { 'https://user:secret@cdn.example.com/sites/' }

    it 'trusts no URL' do
      expect(rule === 'https://cdn.example.com/sites/1/banner.png').to be false
    end

  end

  context 'without a trusted prefix' do

    let(:prefix) { nil }

    it 'trusts no URL' do
      expect { rule.check('http://cdn.example.com/sites/1/banner.png') }.to raise_error(Dragonfly::Job::Fetch::NotFound, /trusted/)
    end

  end

end
