require 'spec_helper'

describe Locomotive::Steam::ImageResizerService::ConvertArguments do

  ['', '-quality 70', '-quality 0', '-quality 100', '-strip', '-interlace Plane', '-auto-orient',
   '-quality 75 -strip -interlace Plane', '-quality 60 -quality 75 -strip -interlace Plane -auto-orient',
   '-quality 60 -quality 75 -strip -interlace Plane -auto-orient -strip -interlace Plane'].each do |arguments|
    it "allows #{arguments.inspect}, as the resize options produce it" do
      expect(described_class.allowed?(arguments)).to be true
    end
  end

  {
    '-write /tmp/copy.png'          => 'writes another file',
    '-quality 70 -write /tmp/x.png' => 'writes another file after a quality',
    'other.png -append'             => 'reads another image',
    '@/etc/passwd'                  => 'reads a file indirectly',
    'msl:script.msl'                => 'names a coder',
    '-sepia-tone 80%'               => 'applies an effect not allowed',
    '-quality 101'                  => 'gives a quality out of range',
    '-quality 7.5'                  => 'gives a quality that is not a whole number',
    '-quality'                      => 'misses a value',
    '-quality -strip'               => 'gives an option as a value',
    '-interlace Line'               => 'interlaces otherwise than the progressive option',
    "-quality '70"                  => 'cannot be split into words',
    '-strip -strip -strip'          => 'repeats an option more than the options can',
    '-quality 60 -quality 70 -quality 80' => 'repeats a quality more than the options can',
    '-auto-orient -auto-orient'     => 'repeats what only auto_orient gives'
  }.each do |arguments, what|
    it "refuses #{arguments.inspect}, which #{what}" do
      expect(described_class.allowed?(arguments)).to be false
    end
  end

  it 'refuses arguments that are not text' do
    expect(described_class.allowed?([{ 'quality' => 70 }])).to be false
  end

end
