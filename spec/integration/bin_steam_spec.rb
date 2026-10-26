require File.dirname(__FILE__) + '/integration_helper'

require 'net/http'
require 'open3'

describe 'bin/steam.rb' do

  let(:root) { File.expand_path('../..', __dir__) }
  let(:port) { TCPServer.open('127.0.0.1', 0) { |server| server.addr[1] } }

  it 'serves a site from its path until it is interrupted' do
    with_steam do |pid, output|
      response = first_response(pid, '/')
      expect([response&.code, response&.body.to_s[/Upcoming events/]]).to eq(['200', 'Upcoming events']), File.read(output)

      Process.kill('INT', pid)
      expect(Timeout.timeout(10) { Process.wait2(pid).last }).to be_success, File.read(output)
    end
  end

  it 'links the assets of a page through the asset host it is given' do
    with_steam('--asset-host', 'https://cdn.example.com') do |pid, output|
      response = first_response(pid, '/')
      expect(response&.code).to eq('200'), File.read(output)
      expect(response.body).to include('href="https://cdn.example.com/stylesheets/application.css'), File.read(output)
    end
  end

  it 'shows its usage for -h' do
    usage, errors, status = Open3.capture3(RbConfig.ruby, 'bin/steam.rb', '-h', chdir: root)

    expect(status).to be_success, errors
    expect(usage).to start_with('Usage: steam.rb [options]'), usage + errors
  end

  def with_steam(*arguments)
    Dir.mktmpdir do |dir|
      output = File.join(dir, 'output')
      pid    = Process.spawn(RbConfig.ruby, 'bin/steam.rb', '--path', 'spec/fixtures/default', '--port', port.to_s,
                             '--log-file', File.join(dir, 'steam.log'), *arguments, chdir: root, [:out, :err] => [output, 'w'])

      begin
        yield pid, output
      ensure
        stop(pid)
      end
    end
  end

  def first_response(pid, path)
    Timeout.timeout(30) do
      Net::HTTP.start('127.0.0.1', port) { |http| http.get(path, 'Host' => 'localhost') }
    rescue Errno::ECONNREFUSED
      return if Process.wait(pid, Process::WNOHANG)
      sleep 0.1
      retry
    end
  rescue Timeout::Error
  end

  def stop(pid)
    Process.kill('KILL', pid)
    Process.wait(pid)
  rescue Errno::ESRCH, Errno::ECHILD
  end

end
