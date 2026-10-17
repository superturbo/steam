require 'spec_helper'

describe Locomotive::Steam::AuthService do

  let(:site)            { instance_double('CurrentSite', _id: 'site-1', domains: ['acme.org', 'localhost'], redirect_to_https: false) }
  let(:password_field)  { instance_double('Field', name: 'password') }
  let(:account_type)    { instance_double('ContentType', password_fields: [password_field]) }
  let(:entries)         { instance_double('ContentService', locale: 'en', get_type: account_type) }
  let(:emails)          { instance_double('EmailService') }
  let(:reset_page)      { instance_double('Page', published?: true, redirect?: false, templatized?: false) }
  let(:page_finder)     { instance_double('PageFinderService', by_handle: reset_page) }
  let(:url_builder)     { instance_double('UrlBuilderService', _url_for: '/account/reset-password') }
  let(:public_origin)   { 'https://acme.org' }
  let(:service)         { described_class.new(site, entries, emails, page_finder: page_finder, url_builder: url_builder, public_origin: public_origin) }
  let(:liquid_context)  { {} }

  let(:default_auth_options) { {
    type:               'accounts',
    id_field:           'email',
    id:                 'john@doe.net',
    password_field:     'password',
    password:           'easyone',
    reset_token:        '42',
    from:               'contact@acme.org',
    subject:            'Instructions for changing your password',
    email_handle:       'reset-password-email',
    smtp:               {}
  } }

  let(:auth_options) { instance_double('AuthOptions', default_auth_options) }

  describe '#sign_up' do

    let(:errors)                { [] }
    let(:entry_attributes)      { { fullname: 'Chris Cornell', band: 'Soundgarden', email: 'chris@soundgarden.band', password: 'easyone', password_confirmation:  'easyone' } }
    let(:entry)                 { instance_double('Account', errors: errors) }
    let(:email_disabled)        { false }
    let(:default_auth_options)  { {
      type:                   'accounts',
      id_field:               'email',
      id:                     'chris@soundgarden.band',
      password_field:         'password',
      from:                   'no-reply@acme.org',
      subject:                'Your account has been created',
      email_handle:           'account-created',
      smtp:                   {},
      disable_email:          email_disabled,
      entry:                  entry_attributes
    } }

    subject { service.sign_up(auth_options, liquid_context) }

    context 'the entry has errors' do

      let(:errors) { [:invalid_password] }

      it 'returns invalid_entry and the entry' do
        expect(entries).to receive(:create).with('accounts', {
          fullname:               'Chris Cornell',
          band:                   'Soundgarden',
          email:                  'chris@soundgarden.band',
          password:               'easyone',
          password_confirmation:  'easyone'
        }).and_return(entry)
        is_expected.to eq [:invalid_entry, entry]
      end

    end

    it "returns both :created and the entry if it was able to create it (+ send email)" do
      expect(entries).to receive(:create).with('accounts', {
        fullname:               'Chris Cornell',
        band:                   'Soundgarden',
        email:                  'chris@soundgarden.band',
        password:               'easyone',
        password_confirmation:  'easyone'
      }).and_return(entry)
      expect(emails).to receive(:send_email).with({
        from:         'no-reply@acme.org',
        to:           'chris@soundgarden.band',
        subject:      'Your account has been created',
        page_handle:  'account-created',
        smtp:         {} }, liquid_context)
      is_expected.to eq [:entry_created, entry]
    end

    context 'email is disabled' do

      let(:email_disabled) { true }

      it "doesn't send a notification email" do
        allow(entries).to receive(:create).and_return(entry)
        expect(emails).to_not receive(:send_email)
        is_expected.to eq [:entry_created, entry]
      end

    end

    { nil => 'is too short (minimum is 6 characters)', '' => 'is too short (minimum is 6 characters)',
      '   ' => 'is too short (minimum is 6 characters)', '      ' => 'is invalid',
      ['easyone'] => 'is invalid', "easy\0one" => 'is invalid', 'ą' * 37 => 'is invalid' }.each do |password, message|
      context "without a usable password: #{password.inspect}" do

        let(:entry_attributes) { { email: 'chris@soundgarden.band', password: password } }
        let(:built)            { Locomotive::Steam::ContentEntry.new({}) }

        it 'refuses it before any host writes the entry' do
          expect(entries).not_to receive(:create)
          expect(entries).to receive(:build).with('accounts', entry_attributes).and_return(built)

          is_expected.to eq [:invalid_entry, built]
          expect(built.errors[:password]).to eq [message]
        end

      end
    end

    describe Locomotive::Steam::AuthService::ContentEntryAuth do

      let(:repository)     { instance_double('FieldRepository', all: nil, required: [], selects: []) }
      let(:password)       { Locomotive::Steam::ContentTypeField.new(name: 'password', type: 'password') }
      let(:fields_by_name) { { password: password }.with_indifferent_access }
      let(:type)           { instance_double('ContentType', slug: 'accounts', label_field_name: :title, fields: repository, fields_by_name: fields_by_name, field_label_of: 'password') }
      let(:attributes)     { { password: 'easyone', password_confirmation: 'easyone' } }
      let(:content_entry)  { Locomotive::Steam::ContentEntry.new(attributes).tap { |e| e.content_type = type } }

      before do
        content_entry.extend(described_class)
        content_entry.password_field = :password
      end

      describe '#valid?' do

        subject { content_entry.valid? }

        it { is_expected.to eq true }

        it 'leaves the password for the write to hash' do
          expect(BCrypt::Password).not_to receive(:create)
          is_expected.to eq true
          expect(content_entry[:password]).to eq 'easyone'
        end

        context 'the password is less than 6 characters' do

          let(:attributes) { { password: 'easy', password_confirmation: 'easy' } }

          it 'returns false' do
            is_expected.to eq false
            expect(content_entry.errors[:password]).to eq(['is too short (minimum is 6 characters)'])
          end

        end

        context "the password doesn't match the confirmation" do

          let(:attributes) { { password: 'easyone', password_confirmation: 'oneeasy' } }

          it 'returns false' do
            is_expected.to eq false
            expect(content_entry.errors[:password_confirmation]).to eq(["doesn't match password"])
          end

        end

        context 'the confirmation is missing' do

          let(:attributes) { { password: 'easyone' } }

          it 'returns false' do
            is_expected.to eq false
            expect(content_entry.errors[:password_confirmation]).to eq(["doesn't match password"])
          end

        end

        ["\xFFeasyone".dup.force_encoding('UTF-8'), "easy\0one"].each do |password|
          context "a password sign in would refuse: #{password.inspect}" do

            let(:attributes) { { password: password, password_confirmation: password } }

            it 'returns false' do
              is_expected.to eq false
              expect(content_entry.errors[:password]).to eq(['is invalid'])
            end

          end
        end

      end

    end

  end

  describe 'an auth type without one password field a visitor may name' do

    let(:auth_options) do
      instance_double('AuthOptions', default_auth_options.merge(entry: nil, disable_email: true))
    end

    shared_examples 'refusing every action' do
      it 'writes nothing and answers each action with its refusal' do
        expect(entries).not_to receive(:create)
        expect(entries).not_to receive(:all)
        expect(entries).not_to receive(:update_decorated_entry)
        allow(entries).to receive(:build).and_return(nil)

        expect(service.sign_up(auth_options, liquid_context)).to eq [:invalid_entry, nil]
        expect(service.sign_in(auth_options, nil)).to eq :wrong_credentials
        expect(service.forgot_password(auth_options, liquid_context)).to eq :wrong_email
        expect(service.reset_password(auth_options, nil)).to eq :invalid_token
      end
    end

    context 'an unknown type' do
      let(:account_type) { nil }
      include_examples 'refusing every action'
    end

    context 'a type with no password field' do
      let(:account_type) { instance_double('ContentType', password_fields: []) }
      include_examples 'refusing every action'
    end

    context 'a type with two password fields' do
      let(:account_type) do
        instance_double('ContentType', password_fields: [password_field, instance_double('Field', name: 'recovery')])
      end
      include_examples 'refusing every action'
    end

    context 'a visitor naming another field' do
      let(:auth_options) do
        instance_double('AuthOptions', default_auth_options.merge(entry: nil, disable_email: true, password_field: 'email'))
      end
      include_examples 'refusing every action'
    end

  end

  describe '#sign_in' do

    subject { service.sign_in(auth_options, nil) }

    it 'returns :wrong_credentials if no entry matches the email' do
      expect(entries).to receive(:all).with('accounts', { 'email' => 'john@doe.net' }).and_return([])
      is_expected.to eq :wrong_credentials
    end

    it "returns :wrong_credentials if the password doesn't the entry's password" do
      entry = account(BCrypt::Password.create('fakeone', cost: 4).to_s)
      expect(entries).to receive(:all).with('accounts', { 'email' => 'john@doe.net' }).and_return([entry])
      is_expected.to eq :wrong_credentials
    end

    it "returns :wrong_credentials if the entry holds no password" do
      [nil, ''].each do |stored|
        allow(entries).to receive(:all).with('accounts', { 'email' => 'john@doe.net' }).and_return([account(stored)])

        expect(service.sign_in(auth_options, nil)).to eq :wrong_credentials
      end
    end

    it "returns both :signed_in and the entry if the password matches the entry's password" do
      entry = account(BCrypt::Password.create('easyone', cost: 4).to_s)
      expect(entries).to receive(:all).with('accounts', { 'email' => 'john@doe.net' }).and_return([entry])
      is_expected.to eq [:signed_in, entry]
    end

    def account(stored_hash)
      field = instance_double('Field', name: :password, type: :password, write_only?: true)
      type  = instance_double('ContentType', fields_by_name: { password: field }.with_indifferent_access)

      Locomotive::Steam::ContentEntry.new(email: 'john@doe.net', password_hash: stored_hash).tap do |entry|
        entry.content_type = type
      end
    end

  end

  describe '#forgot_password' do

    subject { service.forgot_password(auth_options, liquid_context) }

    it 'returns :wrong_email if no entry matches the email' do
      expect(entries).to receive(:all).with('accounts', { 'email' => 'john@doe.net' }).and_return([])
      is_expected.to eq :wrong_email
    end

    it 'sends the instructions by email if an entry matches the email' do
      entry = build_account('42a')
      expect(entries).to receive(:all).with('accounts', { 'email' => 'john@doe.net' }).and_return([entry])
      expect(entries).to receive(:update_decorated_entry)
      expect(emails).to receive(:send_email).with({
        from:         'contact@acme.org',
        to:           'john@doe.net',
        subject:      'Instructions for changing your password',
        page_handle:  'reset-password-email',
        smtp:         {} }, liquid_context)
      is_expected.to eq :reset_password_instructions_sent
      expect(liquid_context['reset_password_url']).to eq 'https://acme.org/account/reset-password?auth_reset_token=42a'
    end

    it 'finds the reset password page by its handle, with its stored state' do
      allow(entries).to receive(:all).and_return([])
      expect(page_finder).to receive(:by_handle).with('reset_password', false).and_return(reset_page)
      is_expected.to eq :wrong_email
    end

    context 'a public origin given by a callable' do

      let(:public_origin) { ->(site) { "http://#{site.domains.last}:3333" } }

      it 'links to the origin it gives for the site' do
        allow(entries).to receive(:all).and_return([build_account('42a')])
        allow(entries).to receive(:update_decorated_entry)
        allow(emails).to receive(:send_email)

        is_expected.to eq :reset_password_instructions_sent
        expect(liquid_context['reset_password_url']).to eq 'http://localhost:3333/account/reset-password?auth_reset_token=42a'
      end

    end

    context 'the current locale and a mount path' do

      let(:site)        { instance_double('CurrentSite', domains: ['acme.org'], redirect_to_https: false, default_locale: 'en', prefix_default_locale: false) }
      let(:reset_page)  { instance_double('Page', published?: true, redirect?: false, templatized?: false, fullpath: 'account/reset-password') }
      let(:url_builder) { Locomotive::Steam::UrlBuilderService.new(site, 'fr', '/locomotive/acme/preview') }

      it 'links to the public path of the page in that locale, without the mount path' do
        allow(entries).to receive(:all).and_return([build_account('42a')])
        allow(entries).to receive(:update_decorated_entry)
        allow(emails).to receive(:send_email)

        is_expected.to eq :reset_password_instructions_sent
        expect(liquid_context['reset_password_url']).to eq 'https://acme.org/fr/account/reset-password?auth_reset_token=42a'
      end

    end

    shared_examples 'no reset link' do |reason|

      it "writes no token and sends no email, and logs that the site has #{reason}" do
        expect(entries).not_to receive(:all)
        expect(entries).not_to receive(:update_decorated_entry)
        expect(emails).not_to receive(:send_email)
        expect(Locomotive::Common::Logger).to receive(:error) do |message|
          expect(message).to include(reason, 'site-1')
          expect(message).not_to match(%r{acme|other|ftp|/x|account/}i)
        end

        is_expected.to eq :reset_password_unavailable
      end

    end

    [nil, ''].each do |origin|

      context "a public origin #{origin.inspect}" do
        let(:public_origin) { origin }
        include_examples 'no reset link', 'no public origin'
      end

    end

    ['https://acme.org/', 'https://acme.org/x', 'https://acme.org?x=1', 'https://acme.org#x', 'https://u@acme.org',
     'ftp://acme.org', 'HTTPS://acme.org', 'https://other.org', 'https://acme.org.other.org', ['https://acme.org'],
     'https://acme.org:', 'https://acme.org:0443'].each do |origin|

      context "a public origin #{origin.inspect}" do
        let(:public_origin) { origin }
        include_examples 'no reset link', 'an invalid or off-site public origin'
      end

    end

    {
      'the HTTPS default port'    => 'https://acme.org:443',
      'the HTTP default port'     => 'http://acme.org:80'
    }.each do |kind, origin|

      context "a public origin with #{kind}" do

        let(:public_origin) { origin }

        it 'links to it' do
          allow(entries).to receive(:all).and_return([build_account('42a')])
          allow(entries).to receive(:update_decorated_entry)
          allow(emails).to receive(:send_email)

          is_expected.to eq :reset_password_instructions_sent
          expect(liquid_context['reset_password_url']).to eq "#{origin}/account/reset-password?auth_reset_token=42a"
        end

      end

    end

    context 'a site served over HTTPS only' do

      let(:site) { instance_double('CurrentSite', _id: 'site-1', domains: ['acme.org'], redirect_to_https: true) }

      context 'with an HTTP public origin' do
        let(:public_origin) { 'http://acme.org' }
        include_examples 'no reset link', 'an invalid or off-site public origin'
      end

      it 'links to its HTTPS origin' do
        allow(entries).to receive(:all).and_return([build_account('42a')])
        allow(entries).to receive(:update_decorated_entry)
        allow(emails).to receive(:send_email)

        is_expected.to eq :reset_password_instructions_sent
        expect(liquid_context['reset_password_url']).to eq 'https://acme.org/account/reset-password?auth_reset_token=42a'
      end

    end

    context 'a site not served over HTTPS only' do

      let(:public_origin) { 'http://ACME.org' }

      it 'keeps the configured HTTP origin' do
        allow(entries).to receive(:all).and_return([build_account('42a')])
        allow(entries).to receive(:update_decorated_entry)
        allow(emails).to receive(:send_email)

        is_expected.to eq :reset_password_instructions_sent
        expect(liquid_context['reset_password_url']).to eq 'http://ACME.org/account/reset-password?auth_reset_token=42a'
      end

    end

    {
      'missing'      => nil,
      'unpublished'  => { published?: false },
      'redirecting'  => { redirect?: true },
      'templatized'  => { templatized?: true }
    }.each do |kind, state|

      context "a reset password page #{kind}" do
        let(:reset_page) { state && instance_double('Page', { published?: true, redirect?: false, templatized?: false }.merge(state)) }
        include_examples 'no reset link', 'no published reset_password page'
      end

    end

    ['/account/reset?x=1', '/account/reset#x', '/account/re set', 'account/reset'].each do |path|

      context "a reset password page at #{path.inspect}" do
        let(:url_builder) { instance_double('UrlBuilderService', _url_for: path) }
        include_examples 'no reset link', 'a reset_password page path that cannot carry the token'
      end

    end

    describe 'two sites under one public_origin callable' do

      let(:public_origin)  { ->(site) { "https://#{site.domains.first}" } }
      let(:other_site)     { instance_double('CurrentSite', _id: 'site-2', domains: ['other.org'], redirect_to_https: false) }
      let(:other_service)  { described_class.new(other_site, entries, emails, page_finder: page_finder, url_builder: url_builder, public_origin: public_origin) }
      let(:other_context)  { {} }

      before do
        allow(entries).to receive(:all).and_return([build_account('42a')], [build_account('42b')])
        allow(emails).to receive(:send_email)
      end

      it 'links each site to its own domain' do
        allow(entries).to receive(:update_decorated_entry)

        expect(service.forgot_password(auth_options, liquid_context)).to eq :reset_password_instructions_sent
        expect(other_service.forgot_password(auth_options, other_context)).to eq :reset_password_instructions_sent
        expect([liquid_context['reset_password_url'], other_context['reset_password_url']]).to eq [
          'https://acme.org/account/reset-password?auth_reset_token=42a',
          'https://other.org/account/reset-password?auth_reset_token=42b'
        ]
      end

      context 'a callable giving both sites the origin of one' do

        let(:public_origin) { ->(_site) { 'https://acme.org' } }

        it 'refuses the other site before writing its token' do
          expect(entries).to receive(:update_decorated_entry).once
          expect(Locomotive::Common::Logger).to receive(:error).with(/site-2/)

          expect(service.forgot_password(auth_options, liquid_context)).to eq :reset_password_instructions_sent
          expect(other_service.forgot_password(auth_options, other_context)).to eq :reset_password_unavailable
          expect(other_context).to be_empty
        end

      end

    end

    context 'no email template' do

      let(:_auth_options) { default_auth_options.merge(email_handle: nil) }
      let(:auth_options)  { instance_double('AuthOptions', _auth_options) }

      it 'also sends the instructions by email with a default email template' do
        entry = build_account('42a')
        expect(entries).to receive(:all).with('accounts', { 'email' => 'john@doe.net' }).and_return([entry])
        expect(entries).to receive(:update_decorated_entry)
        expect(emails).to receive(:send_email).with({
          from:         'contact@acme.org',
          to:           'john@doe.net',
          subject:      'Instructions for changing your password',
          body:         (<<-EMAIL
Hi,
To reset your password please follow the link below: https://acme.org/account/reset-password?auth_reset_token=42a.
Thanks!
EMAIL
          ),
          smtp:         {} }, liquid_context)
        is_expected.to eq :reset_password_instructions_sent
        expect(liquid_context['reset_password_url']).to eq 'https://acme.org/account/reset-password?auth_reset_token=42a'
      end

    end

  end

  describe '#reset_password' do

    let(:request) { instance_double('Request') }
    let(:_auth_options) { default_auth_options }
    let(:auth_options) { instance_double('AuthOptions', _auth_options) }


    subject { service.reset_password(auth_options, request) }

    context 'no auth token' do

      let(:_auth_options) { default_auth_options.merge({ reset_token: '' }) }
      it { is_expected.to eq :invalid_token }

    end

    context 'password too short' do

      let(:_auth_options) { default_auth_options.merge({ password: '' }) }
      it { is_expected.to eq :password_too_short }

    end

    ['      ', "\xFFeasyone".dup.force_encoding('UTF-8'), "easy\0one", ['easyone']].each do |password|
      context "a password sign in would refuse: #{password.inspect}" do

        let(:_auth_options) { default_auth_options.merge({ password: password }) }

        it 'writes nothing' do
          expect(entries).not_to receive(:update_decorated_entry)
          is_expected.to eq :invalid_password
        end

      end
    end

    context 'a password longer than bcrypt reads, counted in bytes' do

      let(:_auth_options) { default_auth_options.merge({ password: 'ą' * 37 }) }

      it 'writes nothing' do
        expect(entries).not_to receive(:update_decorated_entry)
        is_expected.to eq :invalid_password
      end

    end

    context 'expired auth token' do

      it 'returns :invalid_token' do
        entry = instance_double('Account', :[] => (Time.zone.now - 3.hours).iso8601)
        expect(entries).to receive(:all).with('accounts', { '_auth_reset_token' => '42' }).and_return([entry])
        is_expected.to eq :invalid_token
      end

    end

    context 'valid auth token and password' do

      it 'returns :password_reset and entry' do
        entry = instance_double('Account', :[] => (Time.zone.now - 30.minutes).iso8601)
        expect(entries).to receive(:all).with('accounts', { '_auth_reset_token' => '42' }).and_return([entry])
        expect(BCrypt::Password).to receive(:create).with('easyone').and_return('hashedeasyone')
        expect(entries).to receive(:update_decorated_entry).with(entry, { 'password_hash' => 'hashedeasyone', '_auth_reset_token' => nil, '_auth_reset_sent_at' => nil })
        is_expected.to eq [:password_reset, entry]
      end

    end

  end

  def build_account(reset_token)
    instance_double('Account').tap do |entry|
      allow(entry).to receive(:[]).with('_auth_reset_token').and_return(reset_token)
    end
  end

end
