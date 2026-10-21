require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'
require_relative '../../support/adapter_parity_fixture'
require_relative '../../support/adapter_parity_context'

describe 'Adapter parity' do

  shared_examples_for 'the adapter parity dataset' do

    include_context 'adapter parity dataset access'

    describe 'the auth service' do

      include_context 'adapter parity service access'
      include_context 'adapter parity service writing'

      let(:writable_types) { %w(submissions members keyrings patrons) }
      let(:emails)         { instance_double('EmailService', send_email: true) }
      let(:reset_page)     { instance_double('Page', published?: true, redirect?: false, templatized?: false) }
      let(:auth) do
        Locomotive::Steam::AuthService.new(site, service, emails,
          page_finder:    instance_double('PageFinderService', by_handle: reset_page),
          url_builder:    instance_double('UrlBuilderService', _url_for: '/reset'),
          public_origin:  'https://adapter-parity.example.com')
      end

      def options(type, **values)
        instance_double('AuthOptions', {
          type: type, id_field: 'email', id: 'ada@example.com', password_field: nil, password: 'easyone',
          entry: nil, disable_email: true, reset_token: nil,
          from: 'site@example.com', subject: 'Reset', email_handle: nil, smtp: {}
        }.merge(values))
      end

      def stored(type, email)
        entries_of(type).all('email' => email, _visible: nil).first
      end

      def stored_count(type)
        entries_of(type).all(_visible: nil).size
      end

      describe 'with the one password field a type declares' do

        let(:sign_up_entry) { valid.merge(secret: 'easyone', secret_confirmation: 'easyone') }

        before { auth.sign_up(options('submissions', entry: sign_up_entry), ::Liquid::Context.new) }

        it 'signs up through it when no field is named' do
          expect(BCrypt::Password.new(stored('submissions', 'ada@example.com')[:secret_hash])
                   .is_password?('easyone')).to eq true
        end

        it 'signs in through it' do
          status, = auth.sign_in(options('submissions'), nil)

          expect(status).to eq :signed_in
        end

        it 'resets nothing through an email field more than one entry may hold' do
          status = auth.forgot_password(options('submissions'), ::Liquid::Context.new)

          expect(status).to eq :wrong_email
          expect(stored('submissions', 'ada@example.com')[:_auth_reset_token]).to be_nil
          expect(emails).not_to have_received(:send_email)
        end

        it 'welcomes the address the entry stores, not the one the form gives' do
          grace = valid.merge(name: 'Grace', email: 'grace@example.com', secret: 'easyone', secret_confirmation: 'easyone')

          auth.sign_up(options('submissions', entry: grace, id: 'someone@example.org', disable_email: false), ::Liquid::Context.new)

          expect(emails).to have_received(:send_email).once.with(hash_including(to: 'grace@example.com'), anything)
        end

        it 'refuses another field a visitor names, even with the right password' do
          status, = auth.sign_in(options('submissions', password_field: :name), nil)

          expect(status).to eq :wrong_credentials
        end

      end

      describe 'with an email field that names one entry' do

        it 'resets a password, the email going to the address the entry stores' do
          status = auth.forgot_password(options('patrons', id: 'legacy@example.com'), ::Liquid::Context.new)
          token  = stored('patrons', 'legacy@example.com')[:_auth_reset_token]

          reset = auth.reset_password(options('patrons', reset_token: token, password: 'newsecret'), nil)

          expect(status).to eq :reset_secret_instructions_sent
          expect(emails).to have_received(:send_email).with(hash_including(to: 'legacy@example.com'), anything)
          expect(reset.first).to eq :secret_reset
          expect(BCrypt::Password.new(stored('patrons', 'legacy@example.com')[:secret_hash]).is_password?('newsecret')).to eq true
        end

        it 'resets nothing when the address names two entries, whatever the field declares' do
          status = auth.forgot_password(options('patrons', id: 'twin@example.com'), ::Liquid::Context.new)

          expect(status).to eq :wrong_email
          expect(entries_of('patrons').all('email' => 'twin@example.com', _visible: nil).map { |e| e[:_auth_reset_token] }).to eq [nil, nil]
          expect(emails).not_to have_received(:send_email)
        end

        it 'writes the token and the password of an entry still storing another email that is no single address' do
          auth.forgot_password(options('patrons', id: 'legacy@example.com'), ::Liquid::Context.new)
          token = stored('patrons', 'legacy@example.com')[:_auth_reset_token]

          expect(token).to be_present
          expect(auth.reset_password(options('patrons', reset_token: token, password: 'newsecret'), nil).first).to eq :secret_reset
          expect(stored('patrons', 'legacy@example.com')[:backup_email]).to eq 'legacy@example.com, other@example.org'
        end

      end

      {
        'a type with no password field'    => ['members',      { email: 'ada@example.com', passcode: 'easyone', passcode_confirmation: 'easyone' }],
        'a type with two password fields'  => ['keyrings',     { email: 'ada@example.com', pin: 'easyone', pin_confirmation: 'easyone' }],
        'an unknown type'                  => ['no-such-type', { email: 'ada@example.com', password: 'easyone', password_confirmation: 'easyone' }]
      }.each do |label, (type, entry)|
        describe label do

          it 'answers every action with its refusal and writes nothing' do
            counts = writable_types.to_h { |name| [name, stored_count(name)] }

            sign_up = auth.sign_up(options(type, entry: entry), ::Liquid::Context.new)

            expect(sign_up.first).to eq :invalid_entry
            expect(auth.sign_in(options(type), nil)).to eq :wrong_credentials
            expect(auth.forgot_password(options(type), ::Liquid::Context.new)).to eq :wrong_email
            expect(auth.reset_password(options(type, reset_token: 'token-1'), nil)).to eq :invalid_token
            expect(writable_types.to_h { |name| [name, stored_count(name)] }).to eq counts
          end

        end
      end

    end

  end

  context 'MongoDB' do

    before(:all) { AdapterParityFixture.seed_mongodb! }
    after(:all)  { AdapterParityFixture.cleanup! }

    it_should_behave_like 'the adapter parity dataset' do
      let(:adapter)  { AdapterParityFixture.mongodb_adapter }

      def filesystem?; false; end
    end

  end

  context 'Filesystem' do

    it_should_behave_like 'the adapter parity dataset' do
      let(:adapter) { AdapterParityFixture.filesystem_adapter }

      def filesystem?; true; end
    end

  end

end
