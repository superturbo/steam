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

  describe 'caching the service response' do

    let(:store)   { ActiveSupport::Cache::MemoryStore.new }
    let(:site)    { instance_double('Site', _id: 'site-1') }
    let(:context) { ::Liquid::Context.new(assigns, {}, { services: services, site: site }) }
    let(:calls)   { [] }
    let(:infos)   { [] }
    let(:call)    { '{% consume blog from "http://blog.locomotiveapp.org/api/read", username: "foo", expires_in: 60 %}' }

    before do
      services.cache = store
      allow(services.external_api).to receive(:consume) { |url, options| calls << [url, options]; { 'title' => "Title #{calls.size}" } }
      allow(Locomotive::Common::Logger).to receive(:info) { |message| infos << message }
    end

    def render(source, on: context)
      render_template(source, on)
    end

    def context_for(site_id)
      ::Liquid::Context.new(assigns, {}, { services: services, site: instance_double('Site', _id: site_id) })
    end

    it 'calls the service once while the lifetime lasts, and again after it' do
      2.times { expect(render("#{call}{{ blog.title }}{% endconsume %}")).to eq 'Title 1' }
      expect(calls.size).to eq 1

      Timecop.travel(Time.now + 61) do
        expect(render("#{call}{{ blog.title }}{% endconsume %}")).to eq 'Title 2'
      end
    end

    it 'logs the call only when it reaches the service' do
      2.times { render("#{call}{{ blog.title }}{% endconsume %}") }

      expect(infos.grep(/\[consume\]/).size).to eq 1
    end

    it 'renders each block with the cached response' do
      expect(render("#{call}<h1>{{ blog.title }}</h1>{% endconsume %}")).to eq '<h1>Title 1</h1>'
      expect(render("#{call}<p>{{ blog.title }}</p>{% endconsume %}")).to eq '<p>Title 1</p>'
      expect(calls.size).to eq 1
    end

    it 'keeps sites apart' do
      expect(render("#{call}{{ blog.title }}{% endconsume %}", on: context_for('site-1'))).to eq 'Title 1'
      expect(render("#{call}{{ blog.title }}{% endconsume %}", on: context_for('site-2'))).to eq 'Title 2'
    end

    it 'keeps calls with other options apart' do
      render("#{call}{{ blog.title }}{% endconsume %}")
      other = call.sub('username: "foo"', 'username: "bar"')

      expect(render("#{other}{{ blog.title }}{% endconsume %}")).to eq 'Title 2'
    end

    it 'keeps other passwords and authorization headers apart' do
      render("#{call}{{ blog.title }}{% endconsume %}")
      with_password = call.sub('username: "foo"', 'username: "foo", password: "p2"')
      with_header   = call.sub('username: "foo"', 'username: "foo", header_auth: "Bearer b2"')

      expect(render("#{with_password}{{ blog.title }}{% endconsume %}")).to eq 'Title 2'
      expect(render("#{with_header}{{ blog.title }}{% endconsume %}")).to eq 'Title 3'
    end

    it 'calls the service once for headers given by a variable, and leaves them as they were' do
      allow(services.external_api).to receive(:consume).and_call_original
      allow(Locomotive::Steam::ExternalAPIService).to receive(:get) { calls << :get; double('response', code: 200, parsed_response: { 'title' => 'T' }) }
      headers = { 'Accept' => 'application/json' }
      on      = ::Liquid::Context.new({ 'hdrs' => headers }, {}, { services: services, site: site })
      source  = '{% consume blog from "http://blog.locomotiveapp.org/api/read", headers: hdrs, header_auth: "Bearer t1", with_user_agent: true, expires_in: 60 %}{{ blog.title }}{% endconsume %}'

      2.times { expect(render(source, on: on)).to eq 'T' }

      expect(calls).to eq [:get]
      expect(headers).to eq('Accept' => 'application/json')
    end

    it 'calls the service without the cache when there is no site' do
      without_site = ::Liquid::Context.new(assigns, {}, { services: services })
      expect(store).not_to receive(:fetch)

      2.times { render("#{call}{{ blog.title }}{% endconsume %}", on: without_site) }

      expect(calls.size).to eq 2
    end

    it 'keeps other lifetimes apart' do
      render("#{call}{{ blog.title }}{% endconsume %}")
      longer = call.sub('expires_in: 60', 'expires_in: 3600')

      expect(render("#{longer}{{ blog.title }}{% endconsume %}")).to eq 'Title 2'
    end

    it 'does not cache an empty response' do
      allow(services.external_api).to receive(:consume) { |*| calls << :call; calls.size == 1 ? nil : { 'title' => 'Back' } }

      expect(render("#{call}{% if blog == null %}down{% else %}{{ blog.title }}{% endif %}{% endconsume %}")).to eq 'down'
      expect(render("#{call}{% if blog == null %}down{% else %}{{ blog.title }}{% endif %}{% endconsume %}")).to eq 'Back'
    end

    [0, nil].each do |lifetime|
      it "writes nothing to the cache with expires_in #{lifetime.inspect}" do
        source = lifetime ? call.sub('expires_in: 60', "expires_in: #{lifetime}") : call.sub(', expires_in: 60', '')
        expect(store).not_to receive(:fetch)
        expect(store).not_to receive(:write)

        2.times { render("#{source}{{ blog.title }}{% endconsume %}") }

        expect(calls.size).to eq 2
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

    it 'gives the block nil on a timeout' do
      allow(services.external_api).to receive(:consume).and_raise(Timeout::Error)
      source = %{{% consume blog from "#{url}" %}{% if blog == null %}down{% endif %}{% endconsume %}}

      expect(render_template(source, context)).to eq 'down'
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
