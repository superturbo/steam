require 'digest'

module Locomotive
  module Steam
    class ImageResizerService

      # Slots for the ImageMagick commands that may run at once in the processes sharing one directory: a site slot,
      # then a shared one, each an exclusive lock on a file of its own that a command keeps while it runs.
      class CommandSlots

        class Busy < StandardError; end
        class Unavailable < StandardError; end

        attr_reader :wait

        def initialize(directory:, total:, per_site:, wait:)
          @directory, @total, @per_site, @wait = directory, total, per_site, wait
        end

        # Yields the locked files of a command's slots, taken within one wait for both, and closes them once the block
        # ends. A slot stays taken while any process keeps its file open, a command it was passed to included: never
        # free one with LOCK_UN, which frees it for every holder, and never delete the files of a directory in use.
        def hold(site)
          files = []
          begin
            deadline = now + wait
            lock_one(site_paths(site), deadline, files) if site
            lock_one(shared_paths, deadline, files)
            yield files
          ensure
            files.each(&:close)
          end
        end

        private

        attr_reader :directory, :total, :per_site

        def lock_one(paths, deadline, files)
          loop do
            return if paths.any? { |path| lock(path, files) }

            remaining = deadline - now
            raise Busy, "ImageMagick commands are running in every slot" unless remaining.positive?

            sleep [0.01 + rand * 0.04, remaining].min
          end
        end

        # A file joins the files held before it is locked, so no interrupt leaves a slot locked by no one. A missing
        # directory is never made again: its new files would let commands past the slots still held in the old ones.
        def lock(path, files)
          file = File.open(path, File::RDWR | File::CREAT, 0o600)
          files << file
          return true if file.flock(File::LOCK_EX | File::LOCK_NB)

          files.delete(file).close
          false
        rescue SystemCallError => e
          raise Unavailable, "ImageMagick command slots are unavailable: Steam cannot lock #{path} (#{e.class.name.split('::').last})"
        end

        def shared_paths
          Array.new(total) { |index| File.join(directory, "command-#{index}") }
        end

        def site_paths(site)
          name = Digest::SHA256.hexdigest(site.to_s)[0, 16]
          Array.new(per_site) { |index| File.join(directory, "site-#{name}-#{index}") }
        end

        def now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

      end

    end
  end
end
