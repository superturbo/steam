require 'dragonfly'
require 'fileutils'
require 'shellwords'
require 'tmpdir'

module Locomotive
  module Steam
    class ImageResizerService

      class Shell < ::Dragonfly::Shell

        class LimitExceeded < RuntimeError; end

        STDOUT_LIMIT = 1024 * 1024
        STDERR_LIMIT = 64 * 1024
        GRACE        = 1

        RESOURCE_LIMIT_ENV_KEYS = %w(AREA DISK FILE HEIGHT LIST_LENGTH MAP MEMORY THREAD THROTTLE TIME WIDTH)
                                  .map { |name| "MAGICK_#{name}_LIMIT" }.freeze
        POLICY_PATH = File.expand_path('imagemagick', __dir__).freeze

        SAMPLES_PATH = POLICY_PATH
        SAMPLE       = 'sample.png'
        REFUSED      = { 'PDF' => 'refused.pdf', 'SVG' => 'refused.svg', 'MSVG' => 'refused.svg', 'MVG' => 'refused.mvg' }.freeze
        # A denied format may be reported as unavailable.
        REFUSAL = /by the security policy|no decode delegate|unable to open image `[a-z]+:/

        attr_reader :timeout

        # Dragonfly 1.4 has no public way to replace an app's shell.
        def self.install(app, timeout:)
          raise 'Steam runs ImageMagick in process groups, which Windows does not have' if Gem.win_platform?

          temporary = ENV['MAGICK_TEMPORARY_PATH'].presence
          if temporary && !File.directory?(temporary)
            raise "Steam runs ImageMagick inside MAGICK_TEMPORARY_PATH, which is not a directory: #{temporary}"
          end

          shell = app.instance_variable_get(:@shell)
          unless app.shell.equal?(shell) && (shell.instance_of?(::Dragonfly::Shell) || shell.is_a?(self))
            raise 'Steam cannot bound ImageMagick commands: Dragonfly does not keep its shell where 1.4 does'
          end

          app.instance_variable_set(:@shell, new(timeout: timeout))
        end

        def initialize(timeout:)
          @timeout = timeout
        end

        # Probes sample formats, not every policy rule.
        def check_policy(convert:, identify:)
          Dir.mktmpdir('steam-magick-check-') do |directory|
            png = File.join(SAMPLES_PATH, SAMPLE)

            { 'PNG' => png, 'JPEG' => File.join(directory, 'sample.jpg') }.each do |format, sample|
              command(convert, png, sample) unless sample == png
              command(identify, '-ping', sample)
              command(convert, sample, '-resize', '1x1', File.join(directory, "output#{File.extname(sample)}"))
            rescue CommandFailed, LimitExceeded => e
              raise "Steam cannot resize with this ImageMagick: #{format} cannot be read and written (#{e.message.lines.last.strip})"
            end

            REFUSED.each do |format, name|
              command(identify, '-ping', "#{format.downcase}:#{File.join(SAMPLES_PATH, name)}")
              raise "Steam expects ImageMagick to refuse #{format}, but it reads it"
            rescue CommandFailed => e
              next if e.message.match?(REFUSAL)

              raise "Steam cannot verify that ImageMagick refuses #{format} (#{e.message.lines.last.strip})"
            end
          end
        end

        private

        def run_command(command)
          outputs   = hold_outputs(command)
          directory = Dir.mktmpdir('steam-magick-', ENV['MAGICK_TEMPORARY_PATH'].presence)
          out, out_writer = IO.pipe
          err, err_writer = IO.pipe
          pid = waiter = readers = nil
          # Do not interrupt a spawned child before it has a cleanup path.
          Thread.handle_interrupt(Object => :never) do
            pid = Process.spawn(ENV.slice('PATH', *RESOURCE_LIMIT_ENV_KEYS).merge('MAGICK_TEMPORARY_PATH' => directory, 'MAGICK_CONFIGURE_PATH' => POLICY_PATH), command,
                                unsetenv_others: true, pgroup: true, in: File::NULL, out: out_writer, err: err_writer)
            [out_writer, err_writer].each(&:close)
            waiter  = Process.detach(pid)
            readers = [read(out, STDOUT_LIMIT), read(err, STDERR_LIMIT)]
          rescue Errno::ENOENT => e
            raise_command_failed!(command, nil, e.message)
          end

          finished = watchers_finished?([waiter, *readers], timeout)
          raise LimitExceeded, "ImageMagick command ran past #{timeout}s" unless finished

          (stdout, stdout_cut), (stderr, _) = readers.map(&:value)
          raise LimitExceeded, "ImageMagick command printed more than #{STDOUT_LIMIT} bytes" if stdout_cut
          raise_command_failed!(command, waiter.value.exitstatus, stderr) unless waiter.value.success?

          succeeded = true
          stdout
        ensure
          if waiter
            stop(pid, waiter, readers) unless finished
          elsif pid
            stop_and_reap(pid)
          end
          watchers_finished?(readers, GRACE) if readers
          [out, err, out_writer, err_writer].each { |io| io.close if io && !io.closed? }
          outputs&.each do |output|
            output.truncate(0) unless succeeded
          rescue SystemCallError
            nil
          ensure
            output.close
          end
          FileUtils.remove_entry(directory) if directory && File.exist?(directory)
        end

        # Hold the original output file so cleanup cannot follow a replaced path.
        def hold_outputs(command)
          Shellwords.split(command).filter_map { |argument| hold_output(argument) }
        rescue ArgumentError
          []
        end

        def hold_output(argument)
          return unless File.basename(argument).start_with?('dragonfly') &&
                        File.realpath(File.dirname(argument)) == File.realpath(Dir.tmpdir)

          file = File.open(argument, File::WRONLY | File::NOFOLLOW | File::NONBLOCK)
          stat = file.stat
          return file if stat.file? && stat.size.zero?

          file.close
          nil
        rescue SystemCallError
          nil
        end

        def read(io, limit)
          Thread.new do
            kept, cut = String.new, false
            begin
              while (chunk = io.read(16 * 1024))
                room = limit - kept.bytesize
                kept << chunk.byteslice(0, room) if room > 0
                cut ||= chunk.bytesize > room
              end
            rescue IOError # closed while a process left running still holds the pipe
              nil
            end
            [kept.force_encoding(Encoding.default_external).scrub, cut]
          end
        end

        def watchers_finished?(threads, seconds)
          deadline = now + seconds
          threads.all? { |thread| thread.join([deadline - now, 0].max) }
        end

        # A descendant may remain when the watched process exits during cleanup.
        def stop(pid, waiter, readers)
          signal(pid, 'TERM')
          watchers_finished?([waiter, *readers], GRACE)
          signal(pid, 'KILL')
          waiter.join(GRACE)
        end

        def stop_and_reap(pid)
          signal(pid, 'TERM')
          reap(pid)
          signal(pid, 'KILL')
          reap(pid)
        end

        def reap(pid)
          deadline = now + GRACE
          sleep 0.01 until Process.wait(pid, Process::WNOHANG) || now > deadline
        rescue Errno::ECHILD
          nil
        end

        def now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        def command(*arguments)
          run(arguments.shelljoin, escape: false)
        end

        # macOS may return EPERM for an exited group; cleanup must still finish.
        def signal(pid, name)
          Process.kill(name, -pid)
        rescue Errno::ESRCH, Errno::EPERM
        end

      end

    end
  end
end
