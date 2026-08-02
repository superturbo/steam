require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'

describe Locomotive::Steam::MongoDBAdapter do

  let(:adapter) do
    Locomotive::Steam::MongoDBAdapter.new(database: Spec::MONGODB_DATABASE,
                                          hosts: Spec::MONGODB_HOSTS,
                                          min_pool_size: 2, max_pool_size: 5)
  end

  # Isolate the process-wide client from the rest of the suite.
  before(:all) { described_class.disconnect_session }
  after(:all)  { described_class.disconnect_session }

  describe '#session' do

    subject { adapter.send(:session) }

    it 'hands its pool bounds to the driver' do
      subject['locomotive_sites'].find.count

      pool = subject.cluster.servers.first.pool

      expect(pool.min_size).to eq 2
      expect(pool.max_size).to eq 5
    end

  end

  describe '.disconnect_session' do

    it 'closes and clears the client it built' do
      session = adapter.send(:session)

      session['locomotive_sites'].find.count

      described_class.disconnect_session

      expect(session).to be_closed
      expect(described_class.session).to be_nil
    end

  end

end
