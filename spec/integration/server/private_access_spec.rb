require File.dirname(__FILE__) + '/../integration_helper'

describe 'Private access' do

  include Rack::Test::Methods

  def app
    run_server
  end

  before do
    allow_any_instance_of(Locomotive::Steam::Site).to receive(:private_access).and_return(true)
    allow_any_instance_of(Locomotive::Steam::Site).to receive(:password).and_return('easyone')
  end

  def lock_screen_token
    get '/'
    last_response.body[/name="_csrf" value="([^"]+)"/, 1]
  end

  it 'renders the lock screen with a token' do
    get '/'

    expect(last_response.status).to eq 403
    expect(last_response.body).to match(/name="_csrf" value="[^"]+"/)
  end

  it 'unlocks the site with the password and the token of the lock screen' do
    token = lock_screen_token

    post '/', { 'private_access_password' => 'easyone', '_csrf' => token }
    expect(last_response.status).to eq 200

    get '/'
    expect(last_response.status).to eq 200
  end

  it 'refuses the password without the token' do
    lock_screen_token

    post '/', { 'private_access_password' => 'easyone' }
    expect(last_response.status).to eq 422

    get '/'
    expect(last_response.status).to eq 403
  end

  it 'does not unlock the site from the query string' do
    get '/?private_access_password=easyone'
    expect(last_response.status).to eq 403

    get '/'
    expect(last_response.status).to eq 403
  end

end
