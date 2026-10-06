require 'spec_helper'
require 'open3'

describe Locomotive::Steam::ImageResizerService::Shell do

  let(:shell) { described_class.new(timeout: 0.5) }
  let(:dir)   { Dir.mktmpdir }

  after { FileUtils.remove_entry(dir) if File.exist?(dir) }

  def script(name, body)
    path = File.join(dir, name)
    File.write(path, "#{body}\n")
    "sh #{path}"
  end

  def gone?(pid)
    20.times do
      Process.kill(0, pid)
      sleep 0.05
    end
    false
  rescue Errno::ESRCH
    true
  end

  def pids
    File.read(File.join(dir, 'pids')).split.map(&:to_i)
  end

  def wait_for_pids(seconds = 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    until File.exist?(File.join(dir, 'pids'))
      raise "the command wrote no pids within #{seconds}s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.1
    end
  end

  describe 'a command that finishes' do

    it 'returns what it prints' do
      expect(shell.run("printf 'JPEG 4000 3000'", escape: false)).to eq 'JPEG 4000 3000'
    end

    it 'fails as Dragonfly does when the command fails' do
      expect { shell.run("sh -c 'echo broken >&2; exit 3'", escape: false) }
        .to raise_error(Dragonfly::Shell::CommandFailed, /exit status: 3.*broken/m)
    end

    it 'fails as Dragonfly does when the command does not exist' do
      expect { shell.run('/nonexistent/steam/command') }
        .to raise_error(Dragonfly::Shell::CommandFailed, /No such file or directory/)
    end

  end

  describe 'a command that runs past the timeout' do

    let(:hang) { script('hang', "sleep 30 & echo $$ $! > #{dir}/pids; wait") }

    it 'is stopped with every process it started' do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      expect { shell.run(hang, escape: false) }.to raise_error(described_class::LimitExceeded)

      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 2
      expect(pids.size).to eq 2
      expect(pids.all? { |pid| gone?(pid) }).to be true
    end

    it 'is stopped with a process left in its group that ignores TERM and dropped its output' do
      leftover = script('leftover', "(trap '' TERM; exec sleep 30) >/dev/null 2>&1 & echo $$ $! > #{dir}/pids; wait")

      expect { shell.run(leftover, escape: false) }.to raise_error(described_class::LimitExceeded)

      expect(pids.all? { |pid| gone?(pid) }).to be true
    end

    it 'is stopped with what is left in its group when it ends just past the timeout' do
      leftover = script('leftover', "(trap '' TERM; exec sleep 30) >/dev/null 2>&1 & echo $$ $! > #{dir}/pids")
      allow(Process).to receive(:detach).and_wrap_original do |original, pid|
        original.call(pid).tap do |waiter|
          first, join = true, waiter.method(:join)
          waiter.define_singleton_method(:join) do |*limit|
            next join.call(*limit) unless first

            first = false
            join.call
            nil
          end
        end
      end

      expect { shell.run(leftover, escape: false) }.to raise_error(described_class::LimitExceeded)

      expect(pids.all? { |pid| gone?(pid) }).to be true
    end

    describe 'whose group refuses signals (EPERM)' do

      let!(:real_kill) { Process.method(:kill) }

      before do
        allow(Process).to receive(:kill).and_wrap_original do |original, signal, target|
          target.negative? ? raise(Errno::EPERM) : original.call(signal, target)
        end
      end

      def kill_left_overs
        pids.each { |pid| real_kill.('KILL', pid) rescue nil } if File.exist?(File.join(dir, 'pids'))
      end

      let(:alive) { script('alive', "printf %s \"$MAGICK_TEMPORARY_PATH\" > #{dir}/tmp; sleep 30 & echo $$ $! > #{dir}/pids; wait") }

      it 'does not hang on a live process it may not signal, and cleans up quietly' do
        threads = Thread.list
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        expect do
          expect { shell.run(alive, escape: false) }.to raise_error(described_class::LimitExceeded)
          expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 4
          (Thread.list - threads).each { |thread| thread.join(0.5) }
        end.not_to output.to_stderr

        expect(File.exist?(File.read(File.join(dir, 'tmp')))).to be false
      ensure
        kill_left_overs
      end

      it 'cleans up a group that ended between its timeout and the cleanup' do
        ended = script('ended', "printf %s \"$MAGICK_TEMPORARY_PATH\" > #{dir}/tmp")
        allow(Process).to receive(:detach).and_wrap_original do |original, pid|
          original.call(pid).tap do |waiter|
            first, join = true, waiter.method(:join)
            waiter.define_singleton_method(:join) do |*limit|
              next join.call(*limit) unless first

              first = false
              join.call
              nil
            end
          end
        end

        expect { shell.run(ended, escape: false) }.to raise_error(described_class::LimitExceeded)

        expect(File.exist?(File.read(File.join(dir, 'tmp')))).to be false
      end

      it 'does not hang on a live process it may not signal when it could not watch it' do
        long = described_class.new(timeout: 30)
        allow(Process).to receive(:detach) do
          wait_for_pids
          raise ThreadError, "can't create Thread"
        end
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        expect { long.run(alive, escape: false) }.to raise_error(ThreadError)

        expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 4
        expect(File.exist?(File.read(File.join(dir, 'tmp')))).to be false
      ensure
        kill_left_overs
      end

    end

    it 'is stopped even when it ignores TERM' do
      stubborn = script('stubborn', "trap '' TERM; sleep 30 & echo $$ $! > #{dir}/pids; wait")
      started  = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      expect { shell.run(stubborn, escape: false) }.to raise_error(described_class::LimitExceeded)

      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 3
      expect(pids.all? { |pid| gone?(pid) }).to be true
    end

    it 'fails with an error of its own, which names no command' do
      expect { shell.run(hang, escape: false) }.to raise_error { |error|
        expect(error).not_to be_a(Dragonfly::Shell::CommandFailed)
        expect(error.message).to eq 'ImageMagick command ran past 0.5s'
      }
    end

  end

  describe 'what a command prints' do

    it 'keeps the first 64 KB of its errors' do
      noisy = "sh -c 'head -c 1000000 /dev/zero | tr \"\\\\000\" e >&2; exit 1'"

      expect { shell.run(noisy, escape: false) }.to raise_error(Dragonfly::Shell::CommandFailed) { |error|
        expect(error.message.count('e')).to be_between(64 * 1024, 64 * 1024 + 100)
      }
    end

    it 'refuses an output past 1 MB' do
      expect { shell.run('head -c 1048577 /dev/zero', escape: false) }
        .to raise_error(described_class::LimitExceeded, 'ImageMagick command printed more than 1048576 bytes')
    end

  end

  describe 'the temporary directory of ImageMagick' do

    let(:show) { "sh -c 'printf %s \"$MAGICK_TEMPORARY_PATH\"; touch \"$MAGICK_TEMPORARY_PATH/cache\"'" }

    it 'is one of its own for each command, removed afterwards' do
      first, second = 2.times.map { shell.run(show, escape: false) }

      expect(first).not_to eq second
      expect([first, second].none? { |path| path.empty? || File.exist?(path) }).to be true
    end

    it 'is given to the command only' do
      expect { shell.run(show, escape: false) }.not_to(change { ENV['MAGICK_TEMPORARY_PATH'] })
    end

    describe 'where the host sets one' do

      around do |example|
        kept = ENV['MAGICK_TEMPORARY_PATH']
        example.run
      ensure
        kept ? ENV['MAGICK_TEMPORARY_PATH'] = kept : ENV.delete('MAGICK_TEMPORARY_PATH')
      end

      it 'is made inside it' do
        ENV['MAGICK_TEMPORARY_PATH'] = host = Dir.mktmpdir('host-magick-', dir)

        expect(File.dirname(shell.run(show, escape: false))).to eq host
      end

      it 'is removed when the command does not exist' do
        ENV['MAGICK_TEMPORARY_PATH'] = host = Dir.mktmpdir('host-magick-', dir)

        expect { shell.run('/nonexistent/steam/command') }.to raise_error(Dragonfly::Shell::CommandFailed)
        expect(Dir.children(host)).to be_empty
      end

      it 'is not made elsewhere when the host one does not exist' do
        ENV['MAGICK_TEMPORARY_PATH'] = File.join(dir, 'missing')

        expect { shell.run(show, escape: false) }.to raise_error(Errno::ENOENT)
      end

    end

  end

  describe 'a command whose request is interrupted' do

    # on TERM, the command writes into its directory once more, so a directory
    # removed before the command ended would come back
    let(:late) do
      script('late', <<~SH)
        trap 'mkdir -p "$MAGICK_TEMPORARY_PATH"; touch "$MAGICK_TEMPORARY_PATH/late"; exit 1' TERM
        echo "$MAGICK_TEMPORARY_PATH" > #{dir}/tmp
        sleep 30 & echo $$ $! > #{dir}/pids
        wait
      SH
    end

    let(:timeout_error) { Class.new(Exception) }

    [[:raise, ->(thread, error) { thread.raise(error) }], [:kill, ->(thread, _error) { thread.kill }]].each do |how, interrupt|
      it "stops the command and removes its directory after it ends (#{how})" do
        long  = described_class.new(timeout: 30)
        found = Thread.new do
          long.run(late, escape: false)
        rescue Exception
          nil
        end
        wait_for_pids

        interrupt.(found, timeout_error)
        found.join(5)

        expect(found).not_to be_alive
        expect(pids.all? { |pid| gone?(pid) }).to be true
        expect(File.exist?(File.read(File.join(dir, 'tmp')).strip)).to be false
      end
    end

  end

  describe 'a command interrupted as it starts' do

    let(:late) do
      script('late', <<~SH)
        trap 'mkdir -p "$MAGICK_TEMPORARY_PATH"; touch "$MAGICK_TEMPORARY_PATH/late"; exit 1' TERM
        echo "$MAGICK_TEMPORARY_PATH" > #{dir}/tmp
        sleep 30 & echo $$ $! > #{dir}/pids
        wait
      SH
    end
    let(:long)          { described_class.new(timeout: 30) }
    let(:timeout_error) { Class.new(Exception) }

    def expect_ended_and_cleaned
      expect(pids.all? { |pid| gone?(pid) }).to be true
      expect(File.exist?(File.read(File.join(dir, 'tmp')).strip)).to be false
    end

    [[:raise, ->(thread, error) { thread.raise(error) }], [:kill, ->(thread, _error) { thread.kill }]].each do |how, interrupt|
      it "stops the command when the request is interrupted as soon as it starts (#{how})" do
        started = Queue.new
        allow(Process).to receive(:spawn).and_wrap_original do |original, *arguments, **options|
          original.call(*arguments, **options).tap do
            started << true
            wait_for_pids
            sleep 0.2
          end
        end
        running = Thread.new do
          long.run(late, escape: false)
        rescue Exception
          nil
        end
        expect(started.pop(timeout: 5)).to be(true)

        interrupt.(running, timeout_error)
        running.join(5)

        expect(running).not_to be_alive
        expect_ended_and_cleaned
      end
    end

    it 'stops the command when it cannot be watched at all' do
      allow(Process).to receive(:detach) do
        wait_for_pids
        raise ThreadError, "can't create Thread"
      end

      expect { long.run(late, escape: false) }.to raise_error(ThreadError)

      expect_ended_and_cleaned
    end

    it 'stops a command that ignores TERM when it cannot be watched' do
      stubborn = script('stubborn', "trap '' TERM; sleep 30 & echo $$ $! > #{dir}/pids; wait")
      allow(Process).to receive(:detach) do
        wait_for_pids
        raise ThreadError, "can't create Thread"
      end
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      expect { long.run(stubborn, escape: false) }.to raise_error(ThreadError)

      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 3
      expect(pids.all? { |pid| gone?(pid) }).to be true
    end

    it 'stops the command when it cannot be watched' do
      calls = 0
      allow(Process).to receive(:detach).and_wrap_original do |original, pid|
        calls += 1
        wait_for_pids
        raise Errno::EAGAIN if calls == 1

        original.call(pid)
      end

      expect { long.run(late, escape: false) }.to raise_error(Errno::EAGAIN)

      expect_ended_and_cleaned
    end

  end

  describe 'the output file Dragonfly gives a command' do

    let(:app)     { ::Dragonfly.app(:steam_shell_spec).tap { |app| described_class.install(app, timeout: 0.5) } }
    let(:content) { ::Dragonfly::Content.new(app, 'source') }

    after { ::Dragonfly::App.apps.delete(:steam_shell_spec) }

    def update(command)
      output = nil
      error  = begin
        content.shell_update(escape: false) { |input, path| output = path; "#{command} #{input} #{path}" }
        nil
      rescue RuntimeError => e
        e
      end
      [output, error]
    end

    it 'is emptied when the command runs past the timeout after writing part of it' do
      output, error = update(script('partial', 'head -c 2000000 /dev/zero > "$2"; sleep 30'))

      expect(error).to be_a(described_class::LimitExceeded)
      expect(File.size(output)).to eq 0
    end

    it 'is emptied when the command fails after writing part of it' do
      output, error = update(script('broken', 'head -c 2000000 /dev/zero > "$2"; exit 1'))

      expect(error).to be_a(Dragonfly::Shell::CommandFailed)
      expect(File.size(output)).to eq 0
    end

    it 'keeps what a command that succeeds writes, and the source' do
      output, error = update(script('ok', 'printf done > "$2"'))

      expect(error).to be_nil
      expect(File.read(output)).to eq 'done'
      expect(content.data).to eq 'done'
    end

    # with the garbage collector off, so no finalizer closes a file left open
    it 'closes the output file it holds, whether the command fails or not' do
      descriptors = -> { Dir.children(File.exist?('/proc/self/fd') ? '/proc/self/fd' : '/dev/fd').size }
      update(script('ok', 'printf done > "$2"'))
      GC.disable
      before = descriptors.()

      update(script('ok', 'printf done > "$2"'))
      update(script('broken', 'exit 1'))

      expect(descriptors.()).to eq before
    ensure
      GC.enable
    end

    it 'leaves the source alone when the command fails' do
      source = content.path

      update(script('broken', 'exit 1'))

      expect(File.read(source)).to eq 'source'
    end

    it 'leaves alone a file a link at its name points to' do
      victim = File.join(dir, 'victim').tap { |path| File.write(path, 'keep') }

      update(script('relink', "rm \"$2\"; ln -s #{victim} \"$2\"; exit 1"))

      expect(File.read(victim)).to eq 'keep'
    end

    it 'leaves alone an empty file outside the temporary directory, whatever its name' do
      outside = File.join(dir, 'dragonfly-kept').tap { |path| File.write(path, '') }

      content.shell_update(escape: false) { |_input, _path| "#{script('write', "printf data > #{outside}; exit 1")} #{outside}" } rescue nil

      expect(File.read(outside)).to eq 'data'
    end

    it 'leaves alone what a link with a Dragonfly name points to' do
      victim = File.join(dir, 'victim').tap { |path| File.write(path, '') }
      link   = File.join(Dir.tmpdir, "dragonfly-shell-spec-#{Process.pid}").tap { |path| File.symlink(victim, path) }

      content.shell_update(escape: false) { |_input, _path| "#{script('write', "printf data > #{victim}; exit 1")} #{link}" } rescue nil

      expect(File.read(victim)).to eq 'data'
    ensure
      File.delete(link) if link && File.symlink?(link)
    end

    it 'does not wait on a pipe with a Dragonfly name' do
      fifo     = File.join(Dir.tmpdir, "dragonfly-shell-spec-#{Process.pid}").tap { |path| File.mkfifo(path) }
      updating = Thread.new { content.shell_update(escape: false) { |_input, _path| "#{script('broken', 'exit 1')} #{fifo}" } rescue nil }

      expect(updating.join(3)).not_to be_nil
    ensure
      File.open(fifo, File::RDONLY | File::NONBLOCK, &:close) if updating&.alive?
      updating&.join
      File.delete(fifo) if fifo && File.exist?(fifo)
    end

    it 'leaves alone a file reached through a link on the way to it' do
      outside = File.join(dir, 'outside').tap { |path| FileUtils.mkdir_p(File.join(path, 'sub')) }
      target  = File.join(outside, 'dragonfly-out').tap { |path| File.write(path, '') }
      link    = File.join(Dir.tmpdir, "steam-shell-spec-link-#{Process.pid}").tap { |path| File.symlink(File.join(outside, 'sub'), path) }

      content.shell_update(escape: false) { |_input, _path| "#{script('write', "printf data > #{target}; exit 1")} #{link}/../dragonfly-out" } rescue nil

      expect(File.read(target)).to eq 'data'
    ensure
      File.delete(link) if link && File.symlink?(link)
    end

    it 'leaves alone an empty temporary file Dragonfly did not name' do
      other = File.join(Dir.tmpdir, "steam-shell-spec-#{Process.pid}").tap { |path| File.write(path, '') }

      content.shell_update(escape: false) { |_input, _path| "#{script('write', "printf data > #{other}; exit 1")} #{other}" } rescue nil

      expect(File.read(other)).to eq 'data'
    ensure
      File.delete(other) if other && File.exist?(other)
    end

    it 'does not open what a link at its name points to' do
      fifo   = File.join(dir, 'fifo').tap { |path| File.mkfifo(path) }
      reader = Thread.new { File.open(fifo, 'r', &:read) }
      sleep 0.1

      update(script('relink', "rm \"$2\"; ln -s #{fifo} \"$2\"; exit 1"))

      expect(reader.join(0.3)).to be_nil
    ensure
      File.open(fifo, 'w', &:close) if reader&.alive?
      reader&.join
    end

    it 'does not wait on a pipe that took its name' do
      updating = Thread.new { update(script('repipe', 'rm "$2"; mkfifo "$2"; exit 1')) }

      expect(updating.join(3)).not_to be_nil
    end

    it 'leaves alone another file that took its name' do
      output, _error = update(script('replace', 'rm "$2"; printf other > "$2"; exit 1'))

      expect(File.read(output)).to eq 'other'
    end

    it 'is emptied for a failed job only, while another job succeeds at the same time' do
      other = ::Dragonfly::Content.new(app, 'source')
      done  = Thread.new do
        other.shell_update(escape: false) { |input, path| "#{script('slow', 'sleep 0.3; printf done > "$2"')} #{input} #{path}" }
      end

      output, error = update(script('partial', 'head -c 2000000 /dev/zero > "$2"; sleep 30'))
      done.join

      expect(error).to be_a(described_class::LimitExceeded)
      expect(File.size(output)).to eq 0
      expect(other.data).to eq 'done'
    end

  end

  describe 'with ImageMagick' do

    let(:commands) { ::Dragonfly.app(:steam).env.slice(:convert_command, :identify_command) }
    let(:stock)    { ::Dragonfly.app(:shell_spec_stock).tap { |app| app.configure_with(:imagemagick, commands) } }
    let(:bounded)  { ::Dragonfly.app(:shell_spec_bounded).tap { |app| app.configure_with(:imagemagick, commands); described_class.install(app, timeout: 30) } }

    before { skip 'ImageMagick is not installed' unless File.exist?(commands[:convert_command].to_s) }
    after  { %i(shell_spec_stock shell_spec_bounded).each { |name| ::Dragonfly::App.apps.delete(name) } }

    def image(name)
      File.join(dir, name).tap { |path| system(commands[:convert_command], '-size', '1200x900', 'gradient:red-blue', path, exception: true) }
    end

    def pixels(content)
      Open3.capture2(commands[:identify_command], '-format', '%#', content.path).first
    end

    it 'stops ImageMagick blocked on its input' do
      fifo    = File.join(dir, 'input').tap { |path| File.mkfifo(path) }
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      expect { shell.run("#{commands[:convert_command]} #{fifo} #{dir}/output.png", escape: false) }
        .to raise_error(described_class::LimitExceeded)

      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 2
      expect { File.open(fifo, File::WRONLY | File::NONBLOCK) }.to raise_error(Errno::ENXIO) # no reader left
    end

    it 'resizes a JPEG to the same bytes as Dragonfly' do
      jpeg = image('photo.jpg')

      expect(bounded.fetch_file(jpeg).thumb('300x200#').apply.data).to eq stock.fetch_file(jpeg).thumb('300x200#').apply.data
    end

    it 'resizes a PNG to the same pixels as Dragonfly' do
      png = image('logo.png')

      expect(pixels(bounded.fetch_file(png).thumb('300x200#').apply)).to eq pixels(stock.fetch_file(png).thumb('300x200#').apply)
    end

  end

  describe '.install' do

    let(:app) { ::Dragonfly.app(:steam_shell_install_spec) }

    after { %i(steam_shell_install_spec steam_shell_other_spec).each { |name| ::Dragonfly::App.apps.delete(name) } }

    it 'bounds the commands of one app' do
      other = ::Dragonfly.app(:steam_shell_other_spec)

      described_class.install(app, timeout: 12)

      expect(app.shell).to be_a(described_class)
      expect(app.shell.timeout).to eq 12
      expect(other.shell).to be_instance_of(::Dragonfly::Shell)
    end

    it 'replaces a shell it installed before' do
      described_class.install(app, timeout: 12)
      described_class.install(app, timeout: 20)

      expect(app.shell.timeout).to eq 20
    end

    it 'refuses an app whose shell is not where Dragonfly 1.4 keeps it' do
      app.instance_variable_set(:@shell, Object.new)

      expect { described_class.install(app, timeout: 12) }.to raise_error(RuntimeError, /Dragonfly/)
    end

    it 'refuses a host temporary directory for ImageMagick that does not exist' do
      kept = ENV['MAGICK_TEMPORARY_PATH']
      ENV['MAGICK_TEMPORARY_PATH'] = File.join(dir, 'missing')

      expect { described_class.install(app, timeout: 12) }.to raise_error(RuntimeError, /MAGICK_TEMPORARY_PATH/)
    ensure
      kept ? ENV['MAGICK_TEMPORARY_PATH'] = kept : ENV.delete('MAGICK_TEMPORARY_PATH')
    end

    it 'refuses a platform without process groups' do
      allow(Gem).to receive(:win_platform?).and_return(true)

      expect { described_class.install(app, timeout: 12) }.to raise_error(RuntimeError, /process groups/)
    end

  end

end
