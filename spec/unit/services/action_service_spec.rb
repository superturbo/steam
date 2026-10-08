require 'spec_helper'

describe Locomotive::Steam::ActionService do

  let(:site_hash)      { { 'name' => 'Acme Corp' } }
  let(:site)           { instance_double('Site', as_json: site_hash ) }
  let(:email_service)  { instance_double('EmailService') }
  let(:entry_service)  { instance_double('ContentService') }
  let(:api_service)    { instance_double('ExternalAPIService') }
  let(:redirection_service) { instance_double('PageRedirectionService') }
  let(:cookie_service) { instance_double('CookieService') }
  let(:asset_host)     { Locomotive::Steam::AssetHostService.new(nil, instance_double('Site', asset_host: nil), 'https://assets.example.com') }
  let(:service)        { described_class.new(site, email_service, content_entry: entry_service, api: api_service, redirection: redirection_service, cookie: cookie_service, asset_host: asset_host) }

  def entry(attributes)
    instance_double(Locomotive::Steam::ContentEntry, to_hash: attributes)
  end

  describe '#run' do

    let(:script)  { 'return 1 + 1;' }
    let(:params)  { {} }
    let(:assigns) { {} }
    let(:session) { {} }
    let(:cookies) { {} }
    let(:context) { ::Liquid::Context.new(assigns, {}, { session: session, cookies: cookies }) }

    subject { service.run(script, params, context) }

    it { is_expected.to eq 2.0 }

    describe 'deal with dates (since EPOCH in milliseconds) from a param' do

      let(:params) { { 'api' => { 'title' => 'Hello world', 'sent_at' => 1536598528930 } } }
      let(:script) { "return params.api.sent_at;" }

      it { is_expected.to eq 1536598528930 }

    end

    describe 'deal with exceptions' do

      context 'wrong syntax' do

        let(:script) { 'a +/ b * var;' }

        it 'raises a meaningful exception' do
          expect { subject }.to raise_error(Locomotive::Steam::ActionError, "Action error - unterminated regexp (line 2)")
        end

      end

      context 'other error' do

        let(:script) { 'a.b' }

        it 'raises a meaningful exception' do
          expect { subject }.to raise_error(Locomotive::Steam::ActionError, "Action error - identifier 'a' undefined")
        end

      end

    end

    describe 'with params' do

      let(:params)  { { 'foo' => 'hello' } }
      let(:script)  { "return params.foo + ' world';" }

      it { is_expected.to eq 'hello world' }

      describe "messing with params" do

        let(:script)  { "params.foo += ' world!';" }

        it { is_expected.to eq nil }

        it "can't change a param value" do
          subject
          expect(params['foo']).to eq 'hello'
        end

      end

    end

    describe 'built-in functions / getters / setters' do

      describe 'site' do

        let(:script) { 'return "Name: " + site.name;' }

        it { is_expected.to eq 'Name: Acme Corp' }

      end

      describe 'getProp' do

        let(:assigns) { { 'name' => 'John' } }
        let(:script) { "return getProp('name');" }

        it { is_expected.to eq 'John' }

      end

      describe 'setProp' do

        let(:script) { "return setProp('done', true);" }

        it { subject; expect(context['done']).to eq true }

      end

      describe 'getSessionProp' do

        let(:session) { { name: 'John' } }
        let(:script) { "return getSessionProp('name');" }

        it { is_expected.to eq 'John' }

      end

      describe 'sendSessionProp' do

        let(:script) { "return setSessionProp('done', true);" }

        it { subject; expect(session[:done]).to eq true }

      end

      describe 'getCookiesProp' do

        let(:script) { "return getCookiesProp('name');" }

        it 'should read in the cookie name and return John' do
          expect(cookie_service).to receive(:get).with('name').and_return('John')
          is_expected.to eq('John')
        end

      end

      describe 'setCookiesProp' do

        let(:script) { "return setCookiesProp('done', {'value': true});" }

        it 'should set the cookie done with the value true' do
          expect(cookie_service).to receive(:set).with('done', {'value' => true})
          is_expected.to eq(nil)
        end

      end

      describe 'log' do

        let(:script) { "log('Hello world!');" }

        it 'should call the internal logger to output the log message' do
          expect(Locomotive::Common::Logger).to receive(:info).with('Hello world!')
          is_expected.to eq(nil)
        end

      end

      describe 'allEntries' do

        let(:now)     { Time.use_zone('America/Chicago') { Time.zone.local(2015, 'mar', 25, 10, 0) } }
        let(:assigns) { { 'now' => now } }
        let(:script) {
          <<-JS
            var entries = allEntries('bands', { 'created_at.lte': getProp('now'), published: true });
            var names = []

            for (var i = 0; i < entries.length; i++) {
              names.push(entries[i].name)
            }

            return names.join(', ')
          JS
        }

        before do
          expect(entry_service).to receive(:all).with('bands', { "created_at.lte" => "2015-03-25T10:00:00.000-05:00", "published" => true }).and_return([
            entry('name' => 'Pearl Jam'),
            entry('name' => 'Nirvana'),
            entry('name' => 'Soundgarden')
          ])
        end

        it { is_expected.to eq('Pearl Jam, Nirvana, Soundgarden') }

      end

      describe 'allEntries for an unknown type' do

        let(:script) { "return allEntries('unknown', {}) === null;" }

        before { allow(entry_service).to receive(:all).with('unknown', {}).and_return(nil) }

        it { is_expected.to eq true }

      end

      describe 'findEntry' do

        let(:script) { "return findEntry('bands', '42').name;" }

        before do
          expect(entry_service).to receive(:find).with('bands', '42').and_return(entry('name' => 'Pearl Jam'))
        end

        it { is_expected.to eq('Pearl Jam') }

      end

      describe 'findEntry for a missing entry' do

        let(:script) { "return findEntry('bands', '42') === null;" }

        before { allow(entry_service).to receive(:find).with('bands', '42').and_return(nil) }

        it { is_expected.to eq true }

      end

      describe 'createEntry' do

        let(:script) { "return createEntry('bands', { name: 'Pearl Jam'}).name;" }

        before do
          expect(entry_service).to receive(:create).with('bands', { 'name' => 'Pearl Jam' }).and_return(entry('name' => 'Pearl Jam'))
        end

        it { is_expected.to eq('Pearl Jam') }

      end

      describe 'updateEntry' do

        let(:script) { "return updateEntry('bands', 'pearl-jam', { name: 'Pearl Jam'}).name;" }

        before do
          expect(entry_service).to receive(:update).with('bands', 'pearl-jam', { 'name' => 'Pearl Jam' }).and_return(entry('name' => 'Pearl Jam'))
        end

        it { is_expected.to eq('Pearl Jam') }

      end

      describe 'a file field of an entry' do

        let(:updated_at) { Time.utc(2026, 10, 1, 12) }
        let(:cover)      { Locomotive::Steam::ContentEntry::FileField.new('cover.jpg', '/sites/42/songs/7', 1234, updated_at) }
        let(:song)       { entry('title' => 'Alive', 'cover' => cover) }
        let(:url)        { 'https://assets.example.com/sites/42/songs/7/cover.jpg?1790856000' }

        before do
          allow(entry_service).to receive(:all).with('songs', {}).and_return([song])
          allow(entry_service).to receive(:find).with('songs', 'alive').and_return(song)
          allow(entry_service).to receive(:create).with('songs', { 'title' => 'Alive' }).and_return(song)
          allow(entry_service).to receive(:update).with('songs', 'alive', { 'title' => 'Alive' }).and_return(song)
        end

        {
          'allEntries'  => "allEntries('songs', {})[0]",
          'findEntry'   => "findEntry('songs', 'alive')",
          'createEntry' => "createEntry('songs', { title: 'Alive' })",
          'updateEntry' => "updateEntry('songs', 'alive', { title: 'Alive' })"
        }.each do |name, call|

          context "read through #{name}" do

            let(:script) { "return #{call}.cover.url;" }

            it 'has the asset host and the version of the file' do
              is_expected.to eq url
            end

          end

        end

        context 'without an asset host' do

          let(:asset_host) { Locomotive::Steam::AssetHostService.new(nil, instance_double('Site', asset_host: nil), nil) }
          let(:script)     { "return findEntry('songs', 'alive').cover.url;" }

          it 'keeps the path of the file, with its version' do
            is_expected.to eq '/sites/42/songs/7/cover.jpg?1790856000'
          end

        end

        context 'the rest of the entry' do

          let(:script) { "return findEntry('songs', 'alive');" }

          it 'reads as before' do
            is_expected.to eq(
              'title' => 'Alive',
              'cover' => { 'url' => url, 'filename' => 'cover.jpg', 'size' => 1234.0, 'updated_at' => '2026-10-01T12:00:00.000Z' }
            )
          end

        end

      end

      describe 'sendEmail' do

        let(:params) { { 'to' => 'estelle@locomotivecms.com' } }
        let(:script) { "sendEmail({ to: params.to, from: 'did@locomotivecms.com', subject: 'Happy Easter' })" }

        it 'forwards the action to the email service' do
          expect(email_service).to receive(:send_email).with({
            'to'      => 'estelle@locomotivecms.com',
            'from'    => 'did@locomotivecms.com',
            'subject' => 'Happy Easter' }, context)
          subject
        end

      end

      describe 'callAPI' do

        let(:script) { "callAPI('POST', 'https://api.stripe.com/v1/charges', { username: 'abcdefghij', data: { token: '123456789' } })" }

        it 'forwards the action to the external api service' do
          expect(api_service).to receive(:consume).with(
            'https://api.stripe.com/v1/charges', {
              method: 'POST',
              username: 'abcdefghij',
              data: {
                token: '123456789'
              }
            }, true
          )
          subject
        end

      end

      describe 'redirectTo' do

        let(:script) { "redirectTo('about-us');" }

        it 'stops the rendering process and redirects the user to another page' do
          expect(redirection_service).to receive(:redirect_to).with('about-us', nil).and_raise(Locomotive::Steam::RedirectionException.new('/about-us'))
          expect { subject }.to raise_exception(Locomotive::Steam::RedirectionException, 'Redirect to /about-us (302)')
        end

      end

    end

  end

end
