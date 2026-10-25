require 'spec_helper'

describe Locomotive::Steam::ImageResizerService::CommandSlots do

  let(:directory) { Dir.mktmpdir }
  let(:busy)      { [described_class::Busy, /ImageMagick commands/] }

  after { FileUtils.rm_rf(directory) }

  def slots(total: 2, per_site: 1, wait: 0.2)
    described_class.new(directory: directory, total: total, per_site: per_site, wait: wait)
  end

  # Holds the slots of a command for each site given, one inside the other, while the block runs.
  def holding(*sites, **options, &block)
    return yield if sites.empty?

    slots(**options).hold(sites.first) { holding(*sites.drop(1), **options, &block) }
  end

  def free?(site = nil, **options)
    slots(wait: 0, **options).hold(site) { true }
  rescue described_class::Busy
    false
  end

  # Whether a holder has locked the file of the one slot a site has.
  def site_slot_taken?
    path = Dir.glob(File.join(directory, 'site-*')).first
    path && File.open(path, File::RDWR) { |file| !file.flock(File::LOCK_EX | File::LOCK_NB) }
  end

  def now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def eventually(seconds = 5)
    deadline = now + seconds
    sleep 0.01 until yield || now > deadline
    yield
  end

  it 'gives as many commands a slot as it holds, then makes the next one wait and refuses it' do
    holding(nil, nil) do
      started = now

      expect { slots.hold(nil) {} }.to raise_error(*busy)
      expect(now - started).to be_between(0.2, 1)
    end
  end

  it 'gives the slots back once its block ends, an error included' do
    slots.hold('a') {}
    expect { slots.hold('a') { raise 'stop' } }.to raise_error('stop')

    holding('a', wait: 0) { expect(free?).to be true }
  end

  it 'lets one site take only its own slots, leaving the others for other sites' do
    holding('a') do
      expect { slots.hold('a') {} }.to raise_error(*busy)
      expect(slots.hold('b', &:size)).to eq 2
    end
  end

  it 'waits for both slots within one wait, and keeps no site slot when it finds no shared one' do
    slots.hold('a') {}
    other  = File.open(Dir.glob(File.join(directory, 'site-*')).first, File::RDWR).tap { |file| file.flock(File::LOCK_EX) }
    taking = slots(wait: 1.5)
    clock, site_taken_meanwhile = 0.0, false

    holding(nil, nil) do
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { clock }
      allow(taking).to receive(:sleep) do |seconds|
        clock += seconds
        site_taken_meanwhile ||= other.closed? && site_slot_taken?
        other.close if clock >= 0.6 && !other.closed?
      end

      expect { taking.hold('a') {} }.to raise_error(*busy)
    end

    expect([clock.round(6), site_taken_meanwhile, free?('a')]).to eq [1.5, true, true]
  ensure
    other.close unless other.nil? || other.closed?
  end

  it 'refuses, never fails, when its wait ends between two looks at the clock' do
    holding(nil, nil) do
      clock = 0.0
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { clock += 0.6 }

      expect { slots(wait: 1).hold(nil) {} }.to raise_error(*busy)
    end
  end

  it 'never runs more commands at once than it has slots, across threads' do
    shared           = slots(total: 2, per_site: 2, wait: 5)
    inside, released = Queue.new, Queue.new
    threads          = Array.new(4) { Thread.new { shared.hold('a') { inside << true; released.pop } } }

    2.times { inside.pop }
    sleep 0.1
    expect(inside.size).to eq 0
    4.times { released << true }
    threads.each(&:join)
    expect(inside.size).to eq 2
  end

  it 'gives back the slots of a thread killed while it waits' do
    GC.disable
    holding(nil, nil) do
      waiting = Thread.new { slots(wait: 5).hold('a') {} }
      eventually { site_slot_taken? }
      waiting.kill.join
    end

    expect(free?('a')).to be true
  ensure
    GC.enable
  end

  it 'gives back a slot its thread was killed in the middle of taking, just as it locked the file' do
    GC.disable
    locked = Queue.new
    allow_any_instance_of(File).to receive(:flock).and_wrap_original do |original, *arguments|
      original.call(*arguments).tap do
        next unless Thread.current[:stops_once_locked]

        locked << true
        sleep
      end
    end
    taking = Thread.new do
      Thread.current[:stops_once_locked] = true
      slots(total: 1).hold(nil) {}
    end
    locked.pop
    taking.kill.join

    expect(free?(nil, total: 1)).to be true
  ensure
    GC.enable
  end

  it 'shares its slots with another process using the same directory' do
    directory
    reader, writer = IO.pipe
    pid = fork do
      holding(nil, nil) do
        writer.puts 'held'
        sleep 5
      end
      exit!(0)
    end
    reader.gets

    expect { slots.hold(nil) {} }.to raise_error(*busy)
  ensure
    if pid
      Process.kill('KILL', pid)
      Process.wait(pid)
    end
  end

  it 'refuses a command as unavailable once its directory is gone, never making it again, while an old slot is held' do
    holding('a') do
      FileUtils.rm_rf(directory)

      expect { slots.hold('b') {} }.to raise_error(described_class::Unavailable, /#{Regexp.escape(directory)}/)
      expect(Dir.exist?(directory)).to be false
    end
  end

  it 'takes only a shared slot for a command that names no site' do
    expect(slots.hold(nil, &:size)).to eq 1
    expect(Dir.children(directory)).to all(start_with('command-'))
  end

  it 'names the files of a site by a digest, never by the site itself' do
    slots.hold('../../etc/passwd') {}

    expect(Dir.children(directory)).to all(match(/\A(command|site-\h{16})-\d+\z/))
  end

end
