require 'spec_helper'
require 'socket'

describe Locomotive::Steam::EmailService do

  let(:page)          { nil }
  let(:page_finder)   { instance_double('PageFinder', by_handle: page) }
  let(:liquid_parser) { Locomotive::Steam::LiquidParserService.new(nil, nil) }
  let(:asset_host)    { instance_double('AssetHost') }
  let(:simulation)    { false }
  let(:service)       { described_class.new(page_finder, liquid_parser, asset_host, simulation) }

  # uncomment the line below for DEBUG purpose
  before { allow(service.logger).to receive(:info).and_return(true) }

  describe '#send' do

    let(:enable_starttls_auto) { '0' }
    let(:smtp_options)  { { address: 'smtp.example.com', user_name: 'user', password: 'password', enable_starttls_auto: enable_starttls_auto } }
    let(:options)       { { to: 'john@doe.net', from: 'me@locomotivecms.com', subject: 'Hello world', body: 'Hello {{ to }}', smtp: smtp_options, html: false } }
    let(:context)       { ::Liquid::Context.new({ 'name' => 'John', 'to' => 'john@doe.net' }, {}, {}) }

    subject { service.send_email(options, context) }

    it 'sends the email over Pony' do
      expect(Pony).to receive(:mail).with({
        to:           'john@doe.net',
        from:         'me@locomotivecms.com',
        subject:      'Hello world',
        body:         'Hello john@doe.net',
        via:          :smtp,
        via_options:  {
          address:    'smtp.example.com',
          user_name:  'user',
          password:   'password',
          enable_starttls_auto: false
        }
      })
      subject
    end

    context "enable_starttls_auto is to '1'" do
      let(:enable_starttls_auto) { '1' }

      it 'sends the email over Pony' do
        expect(Pony).to receive(:mail).with({
          to:           'john@doe.net',
          from:         'me@locomotivecms.com',
          subject:      'Hello world',
          body:         'Hello john@doe.net',
          via:          :smtp,
          via_options:  {
            address:    'smtp.example.com',
            user_name:  'user',
            password:   'password',
            enable_starttls_auto: true
          }
        })
        subject
      end
    end

    context 'simulation mode' do

      let(:simulation) { true }

      it "doesn't call Pony.mail" do
        expect(Pony).not_to receive(:mail)
        subject
      end

    end

    describe 'no body, no page handle' do

      let(:options) { { to: 'john@doe.net', from: 'me@locomotivecms.com', subject: 'Hello world', smtp: smtp_options, html: false } }

      it { expect { subject }.to raise_error('[EmailService] the body or page_handle options are missing.')}

    end

    describe 'use a page as the body of the email' do

      let(:page)    { instance_double('Page', liquid_source: '<html><body><h1>Hello {{ name }}</h1></body></html>') }
      let(:options) { { to: 'john@doe.net', from: 'me@locomotivecms.com', subject: 'Hello world', page_handle: 'notification-email', smtp: smtp_options, html: true } }

      it 'sends the email over Pony' do
        expect(Pony).to receive(:mail).with({
          to:           'john@doe.net',
          from:         'me@locomotivecms.com',
          subject:      'Hello world',
          html_body:    '<html><body><h1>Hello John</h1></body></html>',
          via:          :smtp,
          via_options:  {
            address:    'smtp.example.com',
            user_name:  'user',
            password:   'password',
            enable_starttls_auto: false
          }
        })
        subject
      end

      context "the page doesn't exist" do

        let(:page) { nil }

        it { expect { subject }.to raise_error('[EmailService] No page found with the following handle: notification-email') }

      end

    end

    describe 'with attachments' do

      let(:options) { { to: 'john@doe.net', from: 'me@locomotivecms.com', subject: 'Hello world', body: 'Hello {{ to }}', smtp: smtp_options, attachments: attachments, html: false } }

      context 'local attachment' do

        let(:attachments) { { 'foo.txt' => '/local/foo.txt' } }

        around do |example|
          answering('Foo') do |address|
            @address = address
            example.run
          end
        end

        before do
          expect(asset_host).to receive(:compute).with('/local/foo.txt', false).and_return("#{@address}/local/foo.txt")
        end

        it 'sends the email over Pony' do
          expect(Pony).to receive(:mail).with({
            to:           'john@doe.net',
            from:         'me@locomotivecms.com',
            subject:      'Hello world',
            body:         'Hello john@doe.net',
            attachments:  { 'foo.txt' => 'Foo' },
            via:          :smtp,
            via_options:  {
              address:    'smtp.example.com',
              user_name:  'user',
              password:   'password',
              enable_starttls_auto: false
            }
          })
          subject
        end

      end

      context 'remote attachment' do

        let(:address)     { @address }
        let(:attachments) { { 'bar.txt' => "#{address}/bar.txt" } }

        around do |example|
          answering('Bar') do |address|
            @address = address
            example.run
          end
        end

        it 'sends the email over Pony' do
          expect(Pony).to receive(:mail).with({
            to:           'john@doe.net',
            from:         'me@locomotivecms.com',
            subject:      'Hello world',
            body:         'Hello john@doe.net',
            attachments:  { 'bar.txt' => 'Bar' },
            via:          :smtp,
            via_options:  {
              address:    'smtp.example.com',
              user_name:  'user',
              password:   'password',
              enable_starttls_auto: false
            }
          })
          subject
        end

        it 'reads it once, waiting up to 5 seconds to connect and 10 seconds for each read' do
          allow(Net::HTTP).to receive(:start).and_call_original
          allow(Pony).to receive(:mail)

          subject

          expect(Net::HTTP).to have_received(:start).once
            .with('127.0.0.1', URI(address).port, hash_including(open_timeout: 5, read_timeout: 10, max_retries: 0))
        end

        it 'stops reading an attachment whose server never answers after one attempt, keeping no content for it' do
          stub_const("#{described_class}::ATTACHMENT_HTTP_OPTIONS", described_class::ATTACHMENT_HTTP_OPTIONS.merge(read_timeout: 0.2))
          allow(Pony).to receive(:mail)

          stalled do |stalled_address, connections|
            options[:attachments] = { 'bar.txt' => "#{stalled_address}/bar.txt" }

            subject

            expect(Pony).to have_received(:mail).with(hash_including(attachments: { 'bar.txt' => nil }))
            expect(connections.size).to eq 1
          end
        end

        context 'attachment not found' do

          let(:address) { "http://127.0.0.1:#{TCPServer.open('127.0.0.1', 0) { |server| server.addr[1] }}" }

          it 'sends the email with no content for the attachment' do
            expect(Pony).to receive(:mail).with({
              to:           'john@doe.net',
              from:         'me@locomotivecms.com',
              subject:      'Hello world',
              body:         'Hello john@doe.net',
              attachments:  { 'bar.txt' => nil },
              via:          :smtp,
              via_options:  {
                address:    'smtp.example.com',
                user_name:  'user',
                password:   'password',
                enable_starttls_auto: false
              }
            })
            subject
          end

        end

      end

      context 'inline string' do

        let(:attachments) { { 'bar.txt' => 'Bar' } }

        it 'sends the email over Pony' do
          expect(Pony).to receive(:mail).with({
            to:           'john@doe.net',
            from:         'me@locomotivecms.com',
            subject:      'Hello world',
            body:         'Hello john@doe.net',
            attachments:  { 'bar.txt' => 'Bar' },
            via:          :smtp,
            via_options:  {
              address:    'smtp.example.com',
              user_name:  'user',
              password:   'password',
              enable_starttls_auto: false
            }
          })
          subject
        end

      end

    end

  end
  describe 'the log' do

    include_context 'filtered logs'

    let(:logged)  { Hash.new { |hash, level| hash[level] = [] } }
    let(:smtp)    { { address: 'smtp.example.com', port: 587, user_name: 'smtp-user', password: 'smtp-secret', domain: 'example.com' } }
    let(:body)    { 'Reset it here: https://shop.example.lt/reset?auth_reset_token=abc123' }
    let(:options) { { to: 'john@doe.net', from: 'me@locomotivecms.com', subject: 'Your reset link', body: body, smtp: smtp, attachments: { 'invoice.pdf' => 'PDFBYTES' }, html: false } }
    let(:context) { ::Liquid::Context.new({}, {}, {}) }

    before do
      %i(debug info error).each do |level|
        allow(service.logger).to receive(level) { |message| logged[level] << message }
      end
      allow(Pony).to receive(:mail)
    end

    it 'names only the delivery method and the server at info level' do
      service.send_email(options, context)

      expect(logged[:info]).to eq ['[SendEmail] Delivery requested via smtp (smtp.example.com:587)']
    end

    it 'writes the email itself at debug level, without the SMTP settings or the attachment bytes' do
      service.send_email(options, context)

      expect(logged[:debug].join).to include('john@doe.net', 'me@locomotivecms.com', 'Your reset link', 'Reset it here', 'invoice.pdf')
      expect(logged[:debug].join).not_to include('smtp-user', 'smtp-secret', 'PDFBYTES')
    end

    it 'leaves the email out below the debug level' do
      logger = Locomotive::Common::Logger.instance.logger
      level, logger.level = logger.level, ::Logger::INFO

      service.send_email(options, context)

      expect(logged[:debug]).to be_empty
    ensure
      logger.level = level
    end

    context 'in simulation' do

      let(:simulation) { true }

      it 'previews the email at info level, without the SMTP settings or the attachment bytes' do
        service.send_email(options, context)

        expect(logged[:info].join).to include('[SendEmail] Email preview, not sent via smtp (smtp.example.com:587):', 'john@doe.net', 'Your reset link', 'Reset it here', 'invoice.pdf')
        expect(logged[:info].join).not_to include('smtp-user', 'smtp-secret', 'PDFBYTES')
      end

    end

    it 'filters the URL out of an error message that repeats it' do
      url = 'https://files.example.com/private/bar.txt?token=abc'
      options[:attachments] = { 'bar.txt' => url }
      allow(Net::HTTP).to receive(:start).and_raise(URI::InvalidURIError, "bad URI(is not URI?): #{url.inspect}")

      service.send_email(options, context)

      error = logged[:error].find { |message| message.include?('Unable to read') }
      expect(error).to include('URI::InvalidURIError', 'bad URI', 'token=[FILTERED]')
      expect(error).not_to include('token=abc')
    end

    it 'names an attachment it cannot read by its URL, query filtered, and the error' do
      options[:attachments] = { 'bar.txt' => 'https://files.example.com/private/bar.txt?token=abc&v=2' }
      allow(Net::HTTP).to receive(:start).and_raise(SocketError, 'getaddrinfo: nodename nor servname provided')

      service.send_email(options, context)

      error = logged[:error].find { |message| message.include?('Unable to read') }
      expect(error).to include('https://files.example.com/private/bar.txt?token=[FILTERED]&v=2', 'SocketError', 'getaddrinfo')
      expect(error).not_to include('token=abc')
    end

    it "filters the URL of an attachment it cannot read with the host's rules too" do
      options[:attachments] = { 'bar.txt' => 'https://files.example.com/private/bar.txt?access_code=abc&v=2' }
      allow(Net::HTTP).to receive(:start).and_raise(SocketError, 'getaddrinfo: nodename nor servname provided')

      described_class.new(page_finder, liquid_parser, asset_host, simulation, log_rules: [:access_code]).send_email(options, context)

      error = logged[:error].find { |message| message.include?('Unable to read') }
      expect(error).to include('https://files.example.com/private/bar.txt?access_code=[FILTERED]&v=2')
      expect(error).not_to include('access_code=abc')
    end

    it 'takes the rules of the request it is built for by the services' do
      env      = Rack::MockRequest.env_for('/', 'action_dispatch.parameter_filter' => [:access_code])
      services = Locomotive::Steam::Services.build_instance(Rack::Request.new(env))

      expect(services.email.log_rules).to eq [:access_code]
    end

  end

  def answering(body)
    server = TCPServer.new('127.0.0.1', 0)
    thread = Thread.new do
      loop do
        client = server.accept
        while (line = client.gets) && line != "\r\n"; end
        client.write "HTTP/1.1 200 OK\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
        client.close
      end
    rescue IOError, SystemCallError
      nil
    end

    yield "http://127.0.0.1:#{server.addr[1]}"
  ensure
    server&.close
    thread&.join(1)
  end

  def stalled
    server      = TCPServer.new('127.0.0.1', 0)
    connections = Queue.new
    thread      = Thread.new do
      loop { connections << server.accept }
    rescue IOError, SystemCallError
      nil
    end

    yield "http://127.0.0.1:#{server.addr[1]}", connections
  ensure
    server&.close
    thread&.join(1)
    connections.pop.close until connections.nil? || connections.empty?
  end

end
