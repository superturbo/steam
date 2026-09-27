require File.dirname(__FILE__) + '/../integration_helper'

describe 'Resize jobs' do

  include Rack::Test::Methods

  let(:configuration) { Locomotive::Steam.configuration }
  let(:resizer)       { ::Dragonfly.app(:steam) }
  let(:image)         { File.join(default_fixture_site_path, 'public/images/nav_on.png') }
  let(:job)           { resizer.fetch_file(image) }

  def app
    run_server
  end

  def url_signed_with(signing_key)
    kept, resizer.secret = resizer.secret, signing_key
    job.url
  ensure
    resizer.secret = kept
  end

  # The Dragonfly key is global: restore the suite's key once the stubs are gone.
  around do |example|
    example.run
    Locomotive::Steam::Initializers::Dragonfly.new.run
  end

  before do
    allow(configuration).to receive_messages(mode: mode, image_resizer_secret: key)
    Locomotive::Steam::Initializers::Dragonfly.new.run
  end

  shared_examples 'a server running only the jobs it signed' do

    it 'serves a job it signed' do
      get job.url

      expect(last_response.status).to eq 200
      expect(last_response.body).to eq File.binread(image)
    end

    it 'refuses a job signed with the public placeholder' do
      expect_any_instance_of(Dragonfly::Job).not_to receive(:apply)

      get url_signed_with('please change it')
      expect(last_response.status).to eq 400

      head url_signed_with('please change it')
      expect(last_response.status).to eq 400
    end

  end

  context 'with a configured key' do

    let(:mode) { :production }
    let(:key)  { 'a deployment key' }

    it_behaves_like 'a server running only the jobs it signed'

  end

  context 'in test mode without a key' do

    let(:mode) { :test }
    let(:key)  { nil }

    it_behaves_like 'a server running only the jobs it signed'

  end

end
