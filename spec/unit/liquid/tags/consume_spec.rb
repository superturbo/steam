require 'spec_helper'

describe Locomotive::Steam::Liquid::Tags::Consume do

  let(:source)  { '{% consume blog from "http://blog.locomotiveapp.org" %}{% endconsume %}' }
  let(:assigns)   { {} }
  let(:services)  { Locomotive::Steam::Services.build_instance }
  let(:context)   { ::Liquid::Context.new(assigns, {}, { services: services }) }

  subject { render_template(source, context) }

  describe 'validating syntax' do

    let(:response)  { nil }
    before { allow(services.external_api).to receive(:consume).and_return(response) }

    describe 'validates a basic syntax' do
      it { expect { subject }.not_to raise_exception }
    end

    describe 'validates more complex syntax with attributes' do
      let(:source) { '{% consume blog from "http://www.locomotiveapp.org", username: "john", password: password_from_context %}{% endconsume %}' }
      it { expect { subject }.not_to raise_exception }
    end

    describe 'should parse the correct url with complex syntax with attributes' do
      let(:source) { '{% consume blog from "http://www.locomotiveapp.org" username: "john", password: "easyone" %}{% endconsume %}' }
      it { expect { subject }.not_to raise_exception }
    end

    describe 'raises an error if the syntax is incorrect' do
      let(:source) { '{% consume blog http://www.locomotiveapp.org %}{% endconsume %}' }
      it { expect { subject }.to raise_exception(Liquid::SyntaxError) }
    end

  end

  describe 'rendering' do

    let(:response) { { 'title' => 'Locomotive rocks!' } }
    before { allow(services.external_api).to receive(:consume).and_return(response) }

    describe 'assign the response into the liquid variable' do

      let(:source) { "{% consume blog from \"http://blog.locomotiveapp.org/api/read\" %}{{ blog.title }}{% endconsume %}" }
      it { is_expected.to eq 'Locomotive rocks!' }

    end

    describe 'assign the response into the liquid variable using a url from a variable' do

      let(:assigns)   { { 'url' => 'http://blog.locomotiveapp.org/api/read' } }
      let(:source)  { "{% consume blog from url %}{{ blog.title }}{% endconsume %}" }
      it { is_expected.to eq 'Locomotive rocks!' }

    end

    describe 'accept options for the web service' do

      let(:assigns)     { { 'secret_password' => 'bar' } }
      let(:source) { "{% consume blog from \"http://blog.locomotiveapp.org/api/read\", username: 'foo', password: secret_password %}{{ blog.title }}{% endconsume %}" }
      it { is_expected.to eq 'Locomotive rocks!' }

    end

    describe 'inside a loop' do

      let(:assigns) { { 'urls' => ['http://blog.locomotiveapp.org/api/read', 'http://blog.locomotiveapp.org/api/read'] } }
      let(:source)  { "{% for url in urls %}{% consume blog from url %}{{ blog.title }}{% endconsume %}{% endfor %}" }
      it { is_expected.to eq 'Locomotive rocks!Locomotive rocks!' }

    end

    describe "don't render it if the url is blank" do

      let(:source) { "{% consume blog from \"\" %}{{ blog.title }}{% endconsume %}" }
      it { is_expected.to eq '' }

    end

  end

  describe 'with an expires_in option' do

    let(:assigns)     { { 'secret_password' => 'bar' } }
    let(:source)      { "{% consume blog from \"http://blog.locomotiveapp.org/api/read\", username: 'foo', password: secret_password, expires_in: #{expires_in} %}{{ blog.title }}{% endconsume %}" }
    let(:expires_in)  { 42 }

    it 'passes the expires_in value to the cache' do
      expect(services.cache).to receive(:fetch).with('Steam-consume-d1249cd56af82e108d383f981ad953347dbb94dc', { expires_in: 42 }).and_return('Locomotive rocks!')
      is_expected.to eq 'Locomotive rocks!'
    end

    describe 'expires_in set to 0 (so basically, meaning non cache at all)' do

      let(:expires_in)  { 0 }

      it "doesn't pass the expires_in value to the cache" do
        expect(services.cache).to receive(:fetch).with('Steam-consume-d1249cd56af82e108d383f981ad953347dbb94dc', { force: true }).and_return('Locomotive rocks!')
        is_expected.to eq 'Locomotive rocks!'
      end

    end

  end

  describe 'timeout' do

    let(:response)  { { 'title' => 'first response' } }
    let(:url)       { 'http://blog.locomotiveapp.org/api/read' }
    let(:source)    { %{{% consume blog from "#{url}" timeout: 5.0 %}{{ blog.title }}{% endconsume %}} }

    it 'should pass the timeout option to httparty' do
      expect(services.external_api).to receive(:consume).with(url, { timeout: 5.0 }).and_return(response)
      subject
    end

    it 'should return the previous successful response if a timeout occurs' do
      allow(services.cache).to receive(:read).and_return(response)
      allow(services.external_api).to receive(:consume).and_raise(Timeout::Error)
      expect(subject).to eq 'first response'
    end

    describe 'the error line' do

      include_context 'filtered logs'

      let(:url)    { 'http://blog.locomotiveapp.org/api/read?api_key=k123' }
      let(:source) { %{{% consume blog from "#{url}", password: 'p456' %}{{ blog.title }}{% endconsume %}} }
      let(:errors) { [] }

      before do
        allow(Locomotive::Common::Logger).to receive(:error) { |message| errors << message }
        allow(services.external_api).to receive(:consume).and_raise(Net::ReadTimeout, 'timed out reading p456')
      end

      it 'names the call and the timeout, nothing more' do
        subject

        expect(errors).to eq ['[consume] GET http://blog.locomotiveapp.org/api/read?api_key=[FILTERED] timed out (Net::ReadTimeout)']
      end

    end

  end

  describe 'the log' do

    include_context 'filtered logs'

    let(:assigns) { { 'payload' => { 'access_code' => 'a321' } } }
    let(:source)  { "{% consume blog from \"https://api.example.com/v1/posts?api_key=k123&page=2\", username: 'jdoe', password: 'p456', header_auth: 'Bearer h789', data: payload %}{% endconsume %}" }
    let(:info)    { [] }
    let(:debug)   { [] }

    before do
      allow(services.external_api).to receive(:consume).and_return({})
      allow(Locomotive::Common::Logger).to receive(:info) { |message| info << message }
      allow(Locomotive::Common::Logger).to receive(:debug) { |message| debug << message }
    end

    it 'writes the URL and attributes at info level, filtered by name only' do
      subject

      expect(info.join).to include('[consume] https://api.example.com/v1/posts?api_key=[FILTERED]&page=2')
      expect(info.join).to match(/"?password"?:?\s*=?>?\s*"\[FILTERED\]"/)
      expect(info.join).not_to include('k123', 'p456', 'h789')
      expect(debug).to be_empty
    end

    it 'leaves a value whose name no rule covers, such as an API body field' do
      subject

      expect(info.join).to include('a321')
    end

    context 'with headers' do

      let(:source) { "{% consume blog from \"https://api.example.com/v1/posts\", headers: hdrs %}{% endconsume %}" }

      context 'as a hash' do

        let(:assigns) { { 'hdrs' => { 'X-Api-Key' => 'APIKEY99', 'Accept' => 'application/json' } } }

        it 'masks them whole' do
          subject

          expect(info.join).to match(/headers\s*(?::|=>)\s*"\[FILTERED\]"/)
          expect(info.join).not_to include('APIKEY99', 'Accept')
        end

      end

      context 'as text' do

        let(:assigns) { { 'hdrs' => 'Authorization: Bearer abc' } }

        it 'masks them whole' do
          subject

          expect(info.join).to match(/headers\s*(?::|=>)\s*"\[FILTERED\]"/)
          expect(info.join).not_to include('Bearer abc')
        end

      end

    end

    context 'under the host list the request carries' do

      let(:source)  { "{% consume blog from \"https://api.example.com/v1/posts?access_code=q654&page=2\", data: payload %}{% endconsume %}" }
      let(:request) { Rack::Request.new(Rack::MockRequest.env_for('/', 'action_dispatch.parameter_filter' => [:access_code])) }
      let(:context) { ::Liquid::Context.new(assigns, {}, { services: services, request: request }) }

      it 'filters those names too, in the URL and the attributes' do
        subject

        expect(info.join).to include('?access_code=[FILTERED]&page=2')
        expect(info.join).not_to include('q654', 'a321')
      end

    end

  end

end
