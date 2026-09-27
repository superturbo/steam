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

      let(:writable_types) { %w(submissions members keyrings) }
      let(:emails)         { instance_double('EmailService', send_email: true) }
      let(:auth)           { Locomotive::Steam::AuthService.new(site, service, emails) }

      def options(type, **values)
        instance_double('AuthOptions', {
          type: type, id_field: 'email', id: 'ada@example.com', password_field: nil, password: 'easyone',
          entry: nil, disable_email: true, reset_token: nil, reset_password_url: '/reset',
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

        it 'resets through it' do
          status = auth.forgot_password(options('submissions'), ::Liquid::Context.new)
          token  = stored('submissions', 'ada@example.com')[:_auth_reset_token]

          reset = auth.reset_password(options('submissions', reset_token: token, password: 'newsecret'), nil)

          expect(status).to eq :reset_secret_instructions_sent
          expect(reset.first).to eq :secret_reset
          expect(BCrypt::Password.new(stored('submissions', 'ada@example.com')[:secret_hash])
                   .is_password?('newsecret')).to eq true
        end

        it 'refuses another field a visitor names, even with the right password' do
          status, = auth.sign_in(options('submissions', password_field: :name), nil)

          expect(status).to eq :wrong_credentials
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
