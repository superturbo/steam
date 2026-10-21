require 'spec_helper'

require_relative '../../../lib/locomotive/steam/middlewares/concerns/helpers'

describe Locomotive::Steam::Middlewares::Concerns::Helpers do

  let(:middleware)  { Class.new { include Locomotive::Steam::Middlewares::Concerns::Helpers } }
  let(:instance)    { middleware.new }

  describe '#inject_cookies' do

    it 'writes each cookie, leaving the ones kept for the request as they are' do
      cookies = { 'cart' => { 'value' => '1' } }
      allow(instance).to receive(:env).and_return('steam.cookies' => cookies)
      headers = {}

      instance.inject_cookies(headers)

      expect(headers['set-cookie']).to include 'cart=1'
      expect(cookies).to eq('cart' => { 'value' => '1' })
    end

  end

  describe '#redirect_to' do

    subject { instance.redirect_to(location)[1]['location'] }

    context 'mounted_on is not blank' do

      before do
        allow(instance).to receive(:mounted_on).and_return('/my_app')
        allow(instance).to receive(:inject_cookies).and_return(nil)
      end


      let(:location) { '/foo/bar' }
      it { is_expected.to eq '/my_app/foo/bar' }

      describe 'the location already includes mounted_on' do

        let(:location) { '/my_app/foo' }
        it { is_expected.to eq '/my_app/foo' }

      end

    end

  end

end
