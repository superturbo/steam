require 'spec_helper'

describe Locomotive::Steam::LogFilter do

  include_context 'filtered logs'

  describe '.params' do

    it 'masks a value whose name holds a configured part, nested ones included' do
      filtered = described_class.params('auth_id' => 'john@doe.net', 'entry' => { 'name' => 'John', 'password' => 'S1' }, 'header_auth' => 'Bearer T1')

      expect(filtered).to eq('auth_id' => '[FILTERED]', 'entry' => { 'name' => 'John', 'password' => '[FILTERED]' }, 'header_auth' => '[FILTERED]')
    end

    it 'masks the extra names too' do
      expect(described_class.params({ 'name' => 'John' }, [:name])).to eq('name' => '[FILTERED]')
    end

    it 'masks headers whole, as a hash or as text, nested ones included' do
      expect(described_class.params(headers: { 'X-Api-Key' => 'K1', 'Accept' => 'application/json' })).to eq(headers: '[FILTERED]')
      expect(described_class.params(headers: 'Authorization: Bearer abc')).to eq(headers: '[FILTERED]')
      expect(described_class.params('api' => { 'headers' => { 'X-Api-Key' => 'K1' } })).to eq('api' => { 'headers' => '[FILTERED]' })
    end

  end

  describe '.url' do

    it 'masks query values by name, keeping order, separators and repeated keys' do
      expect(described_class.url('https://api.example.com/v1/x?page=2&api_key=K1;tag=a&tag=b&token=T1'))
        .to eq 'https://api.example.com/v1/x?page=2&api_key=[FILTERED];tag=a&tag=b&token=[FILTERED]'
    end

    it 'masks a whole value that holds an equals sign' do
      expect(described_class.url('/x?api_key=abc=def&page=2')).to eq '/x?api_key=[FILTERED]&page=2'
    end

    it 'matches a percent-encoded name, writing the name as given' do
      expect(described_class.url('/x?p%61ssword=P1&page=2')).to eq '/x?p%61ssword=[FILTERED]&page=2'
    end

    it 'writes a URL whose query name decodes to invalid UTF-8 as unparsable' do
      expect(described_class.url('/x?%FF=V1&api_key=K1')).to eq 'an unparsable URL'
    end

    it 'writes a URL with a malformed percent-encoding as unparsable' do
      expect(described_class.url('/x?%zz=V1&api_key=K1')).to eq 'an unparsable URL'
    end

    it "applies a host's Proc rule to the query value itself" do
      rule = ->(key, value) { value.replace('masked') if key == 'page' }

      expect(described_class.url('/x?page=2&q=1', [rule])).to eq '/x?page=masked&q=1'
    end

    it 'masks the user info of a URL without a scheme' do
      expect(described_class.url('//jdoe:P1@api.example.com/v1')).to eq '//[FILTERED]@api.example.com/v1'
      expect(described_class.url('jdoe:P1@api.example.com/v1')).to eq '[FILTERED]@api.example.com/v1'
    end

    it 'leaves an @ in the path alone' do
      expect(described_class.url('https://api.example.com/users/@jdoe')).to eq 'https://api.example.com/users/@jdoe'
    end

    it 'masks the whole user info and drops the fragment' do
      expect(described_class.url('https://jdoe:P1@api.example.com:8443/v1?q=1#secret-part'))
        .to eq 'https://[FILTERED]@api.example.com:8443/v1?q=1'
    end

    it 'reads a URL without a scheme' do
      expect(described_class.url('api.example.com/v1?api_key=K1')).to eq 'api.example.com/v1?api_key=[FILTERED]'
    end

    it 'masks the extra names too' do
      expect(described_class.url('/reset?page=2', [:page])).to eq '/reset?page=[FILTERED]'
    end

    it 'writes neither an unparsable URL nor the parser error' do
      expect(described_class.url('https://api.example.com/v1 x?api_key=K1')).to eq 'an unparsable URL'
    end

  end

  describe 'in test mode, as Wagon runs' do

    before { allow(Locomotive::Steam.configuration).to receive(:mode).and_return(:test) }

    it 'returns every value and URL as given' do
      expect(described_class.params({ 'auth_password' => 'S1', 'name' => 'John' }, [:name])).to eq('auth_password' => 'S1', 'name' => 'John')
      expect(described_class.url('https://jdoe:P1@api.example.com/v1?api_key=K1#part')).to eq 'https://jdoe:P1@api.example.com/v1?api_key=K1#part'
      expect(described_class.url('/x?%FF=V1')).to eq '/x?%FF=V1'
    end

  end

end
