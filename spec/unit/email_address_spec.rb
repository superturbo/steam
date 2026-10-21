require 'spec_helper'

describe 'Locomotive::Steam.email_address?' do

  ['ada@example.com', 'Ada.Lovelace+steam@Example.CO.UK', "o'brien@example.org", 'simonas@veiks', 'a..b@example.com'].each do |address|

    it "takes #{address.inspect}, one address as an email input takes it" do
      expect(Locomotive::Steam.email_address?(address)).to eq true
    end

  end

  ['', 'ada', 'ada@@example.com', 'ada lovelace@example.com', "ada@example.com\n", "ada\r\n@example.com",
   'ada@example.com, grace@example.org', 'grace,ada@example.org', 'Ada <ada@example.com>', "ada\0@example.com",
   "ada@example.com\x7F", "ad\xFFa@example.com".dup.force_encoding('UTF-8'), 'ada@-example.com', 'ada@example-.com',
   'jūratė@example.lt', 'ada@bücher.example', 'ada@[127.0.0.1]'].each do |address|

    it "refuses #{address.inspect}" do
      expect(Locomotive::Steam.email_address?(address)).to eq false
    end

  end

  [nil, 42, :'ada@example.com', ['ada@example.com']].each do |value|

    it "refuses #{value.inspect}, which is no text" do
      expect(Locomotive::Steam.email_address?(value)).to eq false
    end

  end

end
