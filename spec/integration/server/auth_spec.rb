require File.dirname(__FILE__) + '/../integration_helper'

describe 'Authentication' do

  include Rack::Test::Methods

  def app
    run_server
  end

  def post_json(url, params)
    post url, JSON.generate(params.merge(Rack::Csrf.field => form_token)),
         'CONTENT_TYPE' => 'application/json', 'rack.session' => { Rack::Csrf.key => form_token }
  end

  describe 'sign up action' do

    it 'renders the form' do
      get '/account/sign-up'
      expect(last_response.body).to include '/account/sign-up'
    end

    describe 'press the sign up button' do

      let(:params) { {
        auth_action:          'sign_up',
        auth_content_type:    'accounts',
        auth_id_field:        'email',
        auth_password_field:  'password',
        auth_callback:        '/account/me',
        auth_entry: {
          name:                   'Chris Cornell',
          email:                  'chris@soundgarden.band',
          password:               'easyone',
          password_confirmation:  'easyone'
        }
      } }

      it 'redirects to the callback' do
        sign_up(params)
        expect(last_response.status).to eq 303
        expect(last_response.location).to eq '/account/me'
      end

      it 'redirects to the home page without a callback' do
        params.delete(:auth_callback)
        params[:auth_entry][:email] = 'hiro.yamamoto@soundgarden.band'

        sign_up(params)
        expect(last_response.status).to eq 303
        expect(last_response.location).to eq '/'
      end

      it 'accepts the token rendered in the sign up form' do
        get '/account/sign-up'
        token = last_response.body[/name="_csrf" value="([^"]+)"/, 1]
        params[:auth_entry][:email] = 'jeff.ament@soundgarden.band'

        post '/account/sign-up', params.merge(_csrf: token)

        expect(last_response.status).to eq 303
        expect(last_response.location).to eq '/account/me'
      end

      it 'creates the account a lookup by its email finds' do
        params[:auth_entry][:email] = 'matt.cameron@soundgarden.band'
        sign_up(params)

        accounts = last_request.env['steam.services'].content_entry
                     .all('accounts', 'email' => 'matt.cameron@soundgarden.band', '_visible' => nil)
        expect(accounts.size).to eq 1
      end

      it 'stores the password as its hash alone' do
        params[:auth_entry][:email] = 'kim.thayil@soundgarden.band'
        sign_up(params)

        account = last_request.env['steam.services'].content_entry
                    .all('accounts', 'email' => 'kim.thayil@soundgarden.band', '_visible' => nil).first

        expect(account.attributes.keys).not_to include('password', 'password_confirmation', '_password_field')
        expect(BCrypt::Password.new(account.attributes['password_hash']).is_password?('easyone')).to eq true
      end

      it 'signs in with the password it was given, markup included' do
        params[:auth_entry].merge!(email: 'ben.shepherd@soundgarden.band',
                                   password: 'a<b&c>d!', password_confirmation: 'a<b&c>d!')
        sign_up(params)
        clear_cookies

        post_form '/account/sign-in', {
          auth_action: 'sign_in', auth_content_type: 'accounts', auth_id_field: 'email',
          auth_password_field: 'password', auth_id: 'ben.shepherd@soundgarden.band', auth_password: 'a<b&c>d!',
          auth_callback: '/account/me' }
        expect(last_response.status).to eq 303
        expect(last_response.location).to eq '/account/me'
      end

      it 'displays the profile page as described in the params' do
        params[:auth_entry][:email] = 'chris.cornell@soundgarden.band'
        sign_up(params, true)
        expect(last_response.body).to include "My name is Chris Cornell and I'm logged in!"
      end

      context 'wrong parameters' do

        let(:params) { {
          auth_action:          'sign_up',
          auth_content_type:    'accounts',
          auth_id_field:        'email',
          auth_password_field:  'password',
          auth_callback:        '/account/me',
          auth_entry: {
            name:                   'Chris Cornell',
            email:                  'chris@soundgarden.band',
            password:               'easyone',
            password_confirmation:  'easyone2'
          }
        } }

        it 'renders the sign up page with an error message' do
          sign_up(params)
          expect(last_response.status).to eq 200
          expect(last_response.body).to include '/account/sign-up'
          expect(last_response.body).to include "doesn't match password"
        end

      end

      context 'a password of only spaces' do

        before do
          params[:auth_entry][:email] = 'kim@soundgarden.band'
          params[:auth_entry][:password] = params[:auth_entry][:password_confirmation] = '      '
        end

        it 'renders the sign up page with an error message' do
          sign_up(params)
          expect(last_response.status).to eq 200
          expect(last_response.body).to include '/account/sign-up'
          expect(last_response.body).to include 'is invalid'
        end

      end

      %w(_auth_reset_token password_hash).each do |name|
        context "with #{name} in the entry" do

          before do
            params[:auth_entry][:email] = "#{name}@soundgarden.band"
            params[:auth_entry][name.to_sym] = 'token-secret-1'
          end

          it 'renders the sign up page and creates no account' do
            sign_up(params)
            expect(last_response.status).to eq 200
            expect(last_response.body).to include '/account/sign-up'

            accounts = last_request.env['steam.services'].content_entry
                         .all('accounts', 'email' => "#{name}@soundgarden.band", '_visible' => nil)
            expect(accounts).to be_empty

            post_form '/account/sign-in', {
              auth_action: 'sign_in', auth_content_type: 'accounts', auth_id_field: 'email',
              auth_password_field: 'password', auth_id: "#{name}@soundgarden.band", auth_password: 'easyone',
              auth_callback: '/account/me' }
            expect(last_response.body).to include 'Your email and/or password are incorrect'
          end

        end
      end

      def sign_up(params, follow_redirect = false)
        post_form '/account/sign-up', params
        follow_redirect! if follow_redirect
        last_response
      end

    end

  end

  describe 'sign in action' do

    it 'renders the form' do
      get '/account/sign-in'
      expect(last_response.body).to include '/account/sign-in'
      expect(last_response.body).not_to include "You've been signed out"
    end

    describe 'press the sign in button' do

      let(:params) { {
        auth_action:          'sign_in',
        auth_content_type:    'accounts',
        auth_id_field:        'email',
        auth_password_field:  'password',
        auth_id:              'john@doe.net',
        auth_password:        'easyone',
        auth_callback:        '/account/me'
      } }

      it 'redirects to the callback' do
        sign_in(params)
        expect(last_response.status).to eq 303
        expect(last_response.location).to eq '/account/me'
      end

      it 'displays the profile page as described in the params' do
        sign_in(params, true)
        expect(last_response.body).to include "My name is John and I'm logged in!"
      end

      it 'signs in with the fields of the rendered form' do
        get '/account/sign-in'
        fields = last_response.body.scan(/<input type="hidden" name="([^"]+)" value="([^"]*)"/).to_h

        post '/account/sign-in', fields.merge('auth_id' => 'john@doe.net', 'auth_password' => 'easyone')

        expect(last_response.status).to eq 303
        follow_redirect!
        expect(last_request.request_method).to eq 'GET'
        expect(last_response.body).to include "My name is John and I'm logged in!"
      end

      it 'refuses a sign in without the form token' do
        post '/account/sign-in', params
        expect(last_response.status).to eq 422
        expect(last_response.body).to eq 'The form could not be verified. Reload the page and submit it again.'
      end

      context 'wrong credentials' do

        let(:params) { {
          auth_action:          'sign_in',
          auth_content_type:    'accounts',
          auth_id_field:        'email',
          auth_password_field:  'password',
          auth_id:              'john@doe.net',
          auth_password:        'dontrememberit',
          auth_callback:        '/account/me'
        } }

        it 'renders the sign in page with an error message' do
          sign_in(params)
          expect(last_response.status).to eq 200
          expect(last_response.body).to include '/account/sign-in'
          expect(last_response.body).to include 'Your email and/or password are incorrect'
        end

      end

      { auth_content_type: { 'x' => 'accounts' }, auth_id: ['john@doe.net'], auth_id_field: 'password_hash' }.each do |name, value|

        it "signs nobody in, and renders the page, with #{name} #{value.inspect}" do
          sign_in(params.merge(name => value))
          expect(last_response.status).to eq 200
          expect(last_response.body).to include '/account/sign-in'
          expect(last_request.env['rack.session'][:authenticated_entry_id]).to be_nil
        end

      end

      it 'signs in from a JSON body' do
        post_json '/account/sign-in', params
        expect(last_response.status).to eq 303
      end

      { auth_content_type: [42, true], auth_password_field: [42, true] }.each do |name, values|

        values.each do |value|

          it "signs nobody in from a JSON body, and renders the page, with #{name} #{value.inspect}" do
            post_json '/account/sign-in', params.merge(name => value)
            expect(last_response.status).to eq 200
            expect(last_request.env['rack.session'][:authenticated_entry_id]).to be_nil
          end

        end

      end

      context 'a password holding a NUL byte' do

        let(:params) { super().merge(auth_password: "easy\0one") }

        it 'renders the sign in page with an error message' do
          sign_in(params)
          expect(last_response.status).to eq 200
          expect(last_response.body).to include 'Your email and/or password are incorrect'
        end

      end

      def sign_in(params, follow_redirect = false)
        post_form '/account/sign-in', params
        follow_redirect! if follow_redirect
        last_response
      end

    end

  end

  describe 'sign out action' do

    let(:params) { {
      auth_action:          'sign_out',
      auth_content_type:    'accounts'
    } }

    let(:rack_session) { {
      'authenticated_entry_type'  => 'accounts',
      'authenticated_entry_id'    => 'john'
    } }

    context 'a form with _method=delete behind a method override, as in the Engine' do

      def app
        Rack::MethodOverride.new(run_server)
      end

      it 'signs the visitor out' do
        post_form '/account/sign-in', params.merge(_method: 'delete'), { 'rack.session' => rack_session }

        expect(last_response.status).to eq 303
        expect(last_response.location).to eq '/account/sign-in'
      end

    end

    it 'keeps the visitor signed in for a GET request' do
      session = rack_session.merge(Rack::Csrf.key => form_token)
      get '/account/me', params, { 'rack.session' => session, 'HTTP_X_CSRF_TOKEN' => form_token }

      expect(last_response.status).to eq 200
      expect(last_response.body).to include "My name is John and I'm logged in!"
    end

    it 'redirect to the requested page' do
      post_form '/account/sign-in', params, { 'rack.session' => rack_session }
      expect(last_response.status).to eq 303
      expect(last_response.location).to eq "/account/sign-in"
    end

    it 'displays the profile page as described in the params' do
      post_form '/account/sign-in', params, { 'rack.session' => rack_session }
      follow_redirect!
      expect(last_response.body).to include "Sign in"
      expect(last_response.body).not_to include "You're already authenticated!"
    end

  end

  describe 'stopping an impersonation' do

    let(:member) { { 'authenticated_entry_type' => 'accounts', 'authenticated_entry_id' => 'john' } }

    it 'shows the page to an anonymous visitor' do
      get '/about-us?impersonating=stop'
      expect(last_response.status).to eq 200
    end

    it 'shows the page to a visitor whose impersonation is stale' do
      [{ 'authenticated_impersonation' => '1' }, member.merge('authenticated_impersonation' => '1', 'authenticated_entry_id' => 'gone')].each do |stale|
        get '/about-us?impersonating=stop', {}, { 'rack.session' => stale }
        expect([last_response.status, last_response.location]).to eq [200, nil]
      end
    end

    it 'leaves no stale impersonation to a later sign in' do
      post_form '/account/sign-in', {
        auth_action: 'sign_in', auth_content_type: 'accounts', auth_id_field: 'email', auth_password_field: 'password',
        auth_id: 'john@doe.net', auth_password: 'easyone', auth_callback: '/account/me'
      }, { 'rack.session' => { 'authenticated_impersonation' => '1' } }
      follow_redirect!

      expect(last_response.body).to include "My name is John and I'm logged in!"
      expect(last_response.body).not_to include 'locomotive-impersonating-banner'
    end

    it 'keeps a member nobody impersonates signed in' do
      get '/account/me?impersonating=stop', {}, { 'rack.session' => member }
      expect(last_response.status).to eq 200
      expect(last_response.body).to include "My name is John and I'm logged in!"
    end

    it 'keeps an impersonated member signed in on a link, as the stop is a posted form' do
      get '/account/me?impersonating=stop', {}, { 'rack.session' => member.merge('authenticated_impersonation' => '1') }

      expect(last_response.status).to eq 200
      expect(last_response.body).to include "My name is John and I'm logged in!"
      expect(last_response.body).to include 'locomotive-impersonating-banner'
    end

    def submit_the_banner(path)
      session = member.merge('authenticated_impersonation' => '1')

      get path, {}, { 'rack.session' => session }
      form   = Nokogiri::HTML5(last_response.body).at_css('.locomotive-impersonating-banner form')
      fields = form.css('input[type="hidden"]').to_h { |input| [input['name'], input['value']] }

      post form['action'], fields, { 'rack.session' => session }
      form['action']
    end

    it 'signs an impersonated member out from the form of the banner, on a page whose query names other actions' do
      action = submit_the_banner('/account/me?content_type_slug=messages&auth_action=sign_out')

      expect(action).to eq '/account/me'
      expect([last_response.status, last_response.location]).to eq [303, '/account/me']
    end

    context 'without CSRF protection' do

      before { allow(Locomotive::Steam.configuration).to receive(:csrf_protection).and_return(false) }

      it 'signs an impersonated member out from the form of the banner' do
        submit_the_banner('/account/me')

        expect([last_response.status, last_response.location]).to eq [303, '/account/me']
      end

    end

    it 'refuses a posted stop without the form token' do
      post '/account/me', { impersonating: 'stop' }, { 'rack.session' => member.merge('authenticated_impersonation' => '1') }
      expect(last_response.status).to eq 422
    end

  end

  describe 'forgot password action' do

    let(:email)         { '' }
    let(:public_origin) { ->(site) { "http://#{site.domains.first}" } }

    let(:params) { {
      auth_action:                'forgot_password',
      auth_content_type:          'accounts',
      auth_id_field:              'email',
      auth_id:                    email,
      auth_callback:              '/account/sign-in',
      auth_email_handle:          'reset_password_instructions',
    } }

    before { allow(Locomotive::Steam.configuration).to receive(:public_origin).and_return(public_origin) }

    it 'renders the forgot password page with an error message' do
      post_form '/account/forgot-password', params
      expect(last_response.status).to eq 200
      expect(last_response.body).to include 'Forgot your password'
      expect(last_response.body).to include 'Your email is unknown'
    end

    context 'with an known email' do

      let(:email) { 'john@doe.net' }

      it 'sends an email to the account' do
        post_form '/account/forgot-password', params
        expect(last_response.status).to eq 200
        expect(last_response.body).to include "The instructions for changing your password have been emailed to you"
      end

      it 'links to the reset password page at the public origin of the site, whatever the Host and the form say' do
        link = nil
        allow_any_instance_of(Locomotive::Steam::EmailService).to receive(:send_email) { |_, _, context| link = context['reset_password_url'] }

        post_form 'http://sample.lvh.me/account/forgot-password', params.merge(auth_reset_password_url: 'https://evil.example/reset')

        token = last_request.env['steam.services'].content_entry.all('accounts', 'email' => email, '_visible' => nil).first['_auth_reset_token']
        expect(link).to eq "http://example.org/account/reset-password?auth_reset_token=#{token}"
      end

    end

    { auth_content_type: { 'x' => 'accounts' }, auth_id: ['john@doe.net', 'someone@example.org'] }.each do |name, value|

      it "sends no email, and renders the page, with #{name} #{value.inspect}" do
        expect_any_instance_of(Locomotive::Steam::EmailService).not_to receive(:send_email)

        post_form '/account/forgot-password', params.merge(auth_id: 'john@doe.net', name => value)

        expect(last_response.status).to eq 200
        expect(last_response.body).to include 'Forgot your password'
        account = last_request.env['steam.services'].content_entry.all('accounts', 'email' => 'john@doe.net', '_visible' => nil).first
        expect(account['_auth_reset_token']).to be_nil
      end

    end

    { 'name' => 'John', 'password_hash' => 'x', 'nope' => 'john@doe.net' }.each do |id_field, id|

      it "answers a reset by #{id_field}, a field other than an email one, as one for an unknown address" do
        expect_any_instance_of(Locomotive::Steam::EmailService).not_to receive(:send_email)

        post_form '/account/forgot-password', params.merge(auth_id_field: id_field, auth_id: id)

        expect(last_response.status).to eq 200
        expect(last_response.body).to include 'Your email is unknown'
        account = last_request.env['steam.services'].content_entry.all('accounts', 'email' => 'john@doe.net', '_visible' => nil).first
        expect(account['_auth_reset_token']).to be_nil
      end

    end

    context 'without a public origin for the site' do

      let(:email)         { 'no.origin@soundgarden.band' }
      let(:public_origin) { nil }

      it 'answers 503, and writes no token and sends no email' do
        post_form '/account/sign-up', {
          auth_action: 'sign_up', auth_content_type: 'accounts', auth_password_field: 'password',
          auth_entry: { name: 'No Origin', email: email, password: 'easyone', password_confirmation: 'easyone' } }
        clear_cookies
        expect_any_instance_of(Locomotive::Steam::EmailService).not_to receive(:send_email)

        post_form '/account/forgot-password', params

        expect([last_response.status, last_response.body]).to eq [503, 'The password cannot be reset at the moment.']
        account = last_request.env['steam.services'].content_entry.all('accounts', 'email' => email, '_visible' => nil).first
        expect(account['_auth_reset_token']).to be_nil
      end

    end

  end

  describe 'reset password action' do

    let(:token) { '' }
    let(:new_password) { 'newone!' }

    let(:params) { {
      auth_action:                'reset_password',
      auth_content_type:          'accounts',
      auth_password_field:        'password',
      auth_password:              new_password,
      auth_reset_token:           token,
      auth_callback:              '/account/me'
    } }

    it 'renders the reset password page with an error message' do
      post_form '/account/reset-password', params
      expect(last_response.status).to eq 200
      expect(last_response.body).to include 'Change your password'
      expect(last_response.body).to include 'The reset token is not valid anymore'
    end

    describe 'the link of the email' do

      def privacy_headers(path)
        get path
        [last_response.status, last_response.headers['cache-control'], last_response.headers['referrer-policy']]
      end

      it 'opens the page out of caches and referrers' do
        expect(privacy_headers('/account/reset-password?auth_reset_token=42a')).to eq [200, 'no-store', 'no-referrer']
      end

      it 'keeps a missing page out of them too' do
        expect(privacy_headers('/account/no-such-page?auth_reset_token=42a')).to eq [404, 'no-store', 'no-referrer']
      end

      it 'keeps a locale redirect out of them too' do
        expect(privacy_headers('/en/account/reset-password?auth_reset_token=42a')).to eq [301, 'no-store', 'no-referrer']
      end

      it 'leaves the page without a token as it is' do
        expect(privacy_headers('/account/reset-password')).to eq [200, 'max-age=0, private, must-revalidate', nil]
      end

    end

    context 'with an expired token' do

      let(:token) { '420000000000001' }

      it 'renders the reset password page with an error message' do
        post_form '/account/reset-password', params
        expect(last_response.status).to eq 200
        expect(last_response.body).to include 'Change your password'
        expect(last_response.body).to include 'The reset token is not valid anymore'
      end

    end

    context 'through the form the page renders' do

      let(:email) { 'kim.reset@soundgarden.band' }

      before { allow(Locomotive::Steam.configuration).to receive(:public_origin).and_return('http://example.org') }

      it 'resets the password with the fields the form sends' do
        post_form '/account/sign-up', {
          auth_action: 'sign_up', auth_content_type: 'accounts', auth_password_field: 'password',
          auth_callback: '/account/me',
          auth_entry: { name: 'Kim', email: email, password: 'easyone', password_confirmation: 'easyone' } }
        clear_cookies

        post_form '/account/forgot-password', {
          auth_action: 'forgot_password', auth_content_type: 'accounts', auth_id_field: 'email', auth_id: email,
          auth_email_handle: 'reset_password_instructions' }
        token = last_request.env['steam.services'].content_entry
                  .all('accounts', 'email' => email, '_visible' => nil).first['_auth_reset_token']

        get "/account/reset-password?auth_reset_token=#{token}"
        fields = last_response.body.scan(/<input type="hidden" name="(\w+)" value="([^"]*)"/).to_h

        post_form '/account/reset-password', fields.merge('auth_password' => new_password)

        expect(last_response.status).to eq 303
        follow_redirect!
        expect(last_response.body).to include "My name is Kim and I'm logged in!"
      end

    end

    context 'with a valid token' do

      let(:token) { '420000000000000' }

      it 'sends an email to the account' do
        post_form '/account/reset-password', params
        expect(last_response.status).to eq 303
        follow_redirect!
        expect(last_response.body).to include "My name is Jane and I'm logged in!"
      end

      context 'with a too short password' do

        let(:new_password) { 'short' }

        it 'renders the reset password page with an error message' do
          post_form '/account/reset-password', params
          expect(last_response.status).to eq 200
          expect(last_response.body).to include 'Change your password'
          expect(last_response.body).to include 'Your password is too short'
        end

      end

      context 'with a password of only spaces' do

        let(:new_password) { '      ' }

        it 'renders the reset password page with an error message' do
          post_form '/account/reset-password', params
          expect(last_response.status).to eq 200
          expect(last_response.body).to include 'Change your password'
          expect(last_response.body).to include 'Your password is not valid'
        end

      end

    end

  end

end


