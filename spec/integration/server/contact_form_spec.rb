require File.dirname(__FILE__) + '/../integration_helper'

describe 'ContactForm' do

  include Rack::Test::Methods

  def app
    run_server
  end

  it 'renders the form' do
    get '/contact'
    expect(last_response.body).to include '/entry_submissions/messages.json'
    expect(last_response.body).to match(/name="_csrf" value="[^"]+"/)
  end

  describe 'form token' do

    let(:entry) { { 'name' => 'John', 'email' => 'j@doe.net', 'message' => 'Bla bla' } }

    it 'accepts the token rendered in the form of the page' do
      get '/events'
      token = last_response.body[/name="_csrf" value="([^"]+)"/, 1]

      post '/events', { 'content_type_slug' => 'messages', 'entry' => entry, '_csrf' => token }

      expect(last_response.status).to eq 301
      expect(last_response.location).to include 'submitted_entry_slug=john'
    end

    it 'refuses a submission without the token' do
      post '/entry_submissions/messages', { 'entry' => entry }

      expect(last_response.status).to eq 422
      expect(last_response.body).to eq 'The form could not be verified. Reload the page and submit it again.'
    end

    it 'refuses a token sent in the query string only' do
      get '/events'
      token = last_response.body[/name="_csrf" value="([^"]+)"/, 1]

      post "/events?_csrf=#{token}", { 'content_type_slug' => 'messages', 'entry' => entry }

      expect(last_response.status).to eq 422
    end

    it 'refuses a token other than the one of the session' do
      get '/events'

      post '/events', { 'content_type_slug' => 'messages', 'entry' => entry, '_csrf' => 'another-token' }

      expect(last_response.status).to eq 422
    end

    it 'accepts the token of the page in the X-CSRF-Token header' do
      get '/events'
      token = last_response.body[/name="_csrf" value="([^"]+)"/, 1]

      post '/events', { 'content_type_slug' => 'messages', 'entry' => entry }, { 'HTTP_X_CSRF_TOKEN' => token }

      expect(last_response.status).to eq 301
    end

    context 'protection disabled by the host' do

      before { allow(Locomotive::Steam.configuration).to receive(:csrf_protection).and_return(false) }

      it 'renders no token and accepts a submission without one' do
        get '/events'
        expect(last_response.body).not_to include 'name="_csrf"'

        post '/events', { 'content_type_slug' => 'messages', 'entry' => entry }

        expect(last_response.status).to eq 301
      end

    end

  end

  describe 'submit a new entry (old version)' do

    let(:url) { '/entry_submissions/messages' }
    let(:params) { {
      'entry' => { 'name' => 'John', 'email' => 'j@doe.net', 'message' => 'Bla bla' },
      'success_callback' => '/events',
      'error_callback' => '/contact' } }
    let(:response) { post_contact_form(url, params, false) }
    let(:status) { response.status }

    describe 'with json request' do

      let(:response) { post_contact_form(url, params, true) }
      let(:entry) { JSON.parse(response.body) }

      context 'unknown content type' do

        let(:url) { '/entry_submissions/foo' }

        it { expect { response }.to raise_error('Unknown content type "foo" or public_submission_enabled property not true') }

      end

      context 'when not valid' do

        let(:params) { {} }

        it 'returns an error status' do
          expect(response.status).to eq 422
        end

        describe 'errors' do

          subject { entry['errors'] }

          it 'lists all the errors' do
            expect(subject['name']).to eq ["can't be blank"]
            expect(subject['email']).to eq ["can't be blank"]
            expect(subject['email']).to eq ["can't be blank"]
          end

        end

      end

      context 'with system input' do

        let(:params) { { 'entry' => { 'name' => 'John', 'email' => 'j@doe.net', 'message' => 'Bla bla', '_visible' => 'false' } } }

        it 'refuses it' do
          expect(response.status).to eq 422
          expect(entry['errors']['_visible']).to eq ['is invalid']
        end

      end

      context 'when valid' do

        it 'returns a success status' do
          expect(response.status).to eq 200
        end

      end

    end

    describe 'with html request' do

      context 'when not valid' do

        let(:params) { { 'error_callback' => '/contact' } }

        it 'returns a success status' do
          expect(response.status).to eq 200
        end

        it 'displays a global error message' do
          expect(response.body.to_s).to include "Form with errors"
        end

        it 'displays errors' do
          expect(response.body.to_s).to include "can't be blank"
        end

        context 'with system input' do

          let(:params) { {
            'entry' => { 'name' => 'John', 'email' => 'j@doe.net', 'message' => 'Bla bla', '_visible' => 'false' },
            'error_callback' => '/contact' } }

          it 'displays the refusal' do
            expect(response.status).to eq 200
            expect(response.body.to_s).to include '_visible: is invalid'
          end

        end

        context 'redirects outside the site' do

          let(:params) { { 'error_callback' => 'http://www.locomotivecms.com' } }

          it 'returns a success status' do
            expect(response.status).to eq 301
          end

        end

      end

      context 'when valid' do

        let(:env)             { {} }
        let(:follow_redirect) { true }
        let(:response)        { post_contact_form(url, params, false, follow_redirect, env) }

        it 'returns a success status' do
          expect(response.status).to eq 200
        end

        it "doesn't display a global error message" do
          expect(response.body.to_s).not_to include "Form with errors"
        end

        it 'displays a success message' do
          expect(response.body.to_s).to include 'Thank you John'
        end

        context 'mounted on a different path than /' do

          let(:env)             { { 'steam.mounted_on' => '/foo/bar/' } }
          let(:follow_redirect) { false }

          it 'redirects to the location prefixed by the mounted_on path' do
            expect(response.location).to match(/\A\/foo\/bar\/\/events\?submitted_type_slug=messages\&submitted_entry_slug=john/)
          end

        end

      end

    end

  end

  describe 'submit a new entry (new version)' do

    let(:url)     { '/events' }
    let(:params)  { {
      'content_type_slug' => 'messages',
      'some_variable'     => '42',
      'entry' => { 'name' => 'John', 'email' => 'j@doe.net', 'message' => 'Bla bla' } } }
    let(:response) { post_contact_form(url, params) }
    let(:status) { response.status }

    context 'when not valid' do

      let(:params) { { 'content_type_slug' => 'messages' } }

      it 'returns a success status' do
        expect(response.status).to eq 200
      end

      it 'displays errors' do
        expect(response.body.to_s).to include "can't be blank"
      end

      describe 'XSS attack' do

        let(:params) { {
          'content_type_slug' => 'messages',
          'entry' => { 'name' => '<script>alert(document.cookie)</script>' }
        } }

        it "doesn't let people to insert malicious JS code" do
          expect(response.body.to_s).not_to include "<script>alert(document.cookie)</script>"
        end

      end

    end

    context 'when valid' do

      let(:response) { post_contact_form(url, params, false, true) }

      it 'returns a success status' do
        expect(response.status).to eq 200
      end

      it 'displays a success message' do
        expect(response.body.to_s).to include 'Thank you John'
      end

      it 'stores hidden fields from the form' do
        expect(response.body.to_s).to include 'Some variable: 42'
      end

    end

    context 'in a different locale' do

      let(:url)       { '/fr/evenements' }
      let(:response)  { post_contact_form(url, params, false, true) }

      it 'returns a success status' do
        expect(response.status).to eq 200
      end

    end

  end

  def post_contact_form(url, params, json = false, follow_redirect = false, env = {})
    params = params.merge(Rack::Csrf.field => form_token)
    env    = env.merge('rack.session' => { Rack::Csrf.key => form_token })

    if json
      url += '.json'
      params = JSON.generate(params.symbolize_keys)
      env['CONTENT_TYPE'] = 'application/json'
    end

    post url, params, env

    follow_redirect! if follow_redirect

    last_response
  end

end
