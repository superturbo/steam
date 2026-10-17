require 'spec_helper'

require_relative '../../../lib/locomotive/steam/middlewares/concerns/helpers'

describe Locomotive::Steam::Middlewares::Concerns::Helpers do

  let(:middleware)  { Class.new { include Locomotive::Steam::Middlewares::Concerns::Helpers } }
  let(:instance)    { middleware.new }

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
