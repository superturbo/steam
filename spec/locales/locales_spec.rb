require 'spec_helper'

describe "#locales" do

  Dir.glob('config/locales/**/*.yml').each do |locale_file|
    describe "#{locale_file}" do
      it_behaves_like 'my valid locale file' do
        let(:locale_file) { locale_file }
      end
    end

    it "#{locale_file} names every error message en.yml names" do
      english  = YAML.load_file('config/locales/en.yml')['en'].dig('errors', 'messages')
      messages = YAML.load_file(locale_file).values.first.dig('errors', 'messages')

      expect(english.keys - messages.keys).to be_empty
      expect(messages.values_at(*english.keys)).to all(be_present)
    end

    # unless locale_file == 'config/locales/en.yml'
    #   describe "#{locale_file}" do
    #     it_behaves_like 'complete translation of' do
    #       let(:locale_target) { locale_file }
    #     end
    #   end
    # end

  end

end
