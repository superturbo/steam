require 'spec_helper'

describe Locomotive::Steam::Liquid::HtmlEscapedText do

  let(:text) { described_class.new('a&b') }

  it 'reads as the HTML of its text' do
    expect(text).to eq 'a&amp;b'
  end

  it 'gives back the text it escaped' do
    expect(described_class.original(text)).to eq 'a&b'
    expect(described_class.escape(text)).to eq 'a&amp;b'
  end

  it 'gives it back from a copy whose HTML is unchanged' do
    expect(described_class.original(text.dup)).to eq 'a&b'
  end

  it 'gives it up once a copy changes' do
    changed = text.dup << 'z'

    expect(described_class.original(changed)).to equal changed
    expect(described_class.escape(changed)).to eq 'a&amp;amp;bz'
  end

  it 'keeps the text it escaped when its source changes' do
    source  = +'a&b'
    escaped = described_class.new(source)
    source << 'z'

    expect(described_class.original(escaped)).to eq 'a&b'
  end

  it 'maps its text into the escaped text of the result' do
    mapped = described_class.map(text) { |value| "#{value}?c=1" }

    expect(mapped).to eq 'a&amp;b?c=1'
    expect(described_class.original(mapped)).to eq 'a&b?c=1'
  end

  it 'maps a changed copy and any other value as plain text' do
    changed = text.dup << 'z'

    expect(described_class.map(changed) { |value| "#{value}!" }).to be_an_instance_of(String).and eq 'a&amp;bz!'
    expect(described_class.map('a&b') { |value| "#{value}!" }).to be_an_instance_of(String).and eq 'a&b!'
  end

  it 'leaves any other value as it is' do
    expect(described_class.original('a&amp;b')).to eq 'a&amp;b'
    expect(described_class.original(nil)).to be_nil
    expect(described_class.escape('a&b')).to eq 'a&amp;b'
  end

end
