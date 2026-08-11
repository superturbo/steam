require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'

describe Locomotive::Steam::MongoDBAdapter do

  describe '.build_session' do

    around do |example|
      previous = described_class.instance_variable_get(:@session)
      described_class.instance_variable_set(:@session, nil)
      example.run
    ensure
      described_class.instance_variable_set(:@session, previous)
    end

    it 'refuses unacknowledged writes and closes the client' do
      concern = instance_double('Mongo::WriteConcern::Unacknowledged', acknowledged?: false)
      client  = instance_double('Mongo::Client', write_concern: concern, close: nil)
      allow(Mongo::Client).to receive(:new).and_return(client)

      expect { described_class.build_session(['127.0.0.1:27017'], {}) }
        .to raise_error(ArgumentError, /acknowledged/)

      expect(client).to have_received(:close)
      expect(described_class.session).to be_nil
    end

    it 'accepts the driver default concern' do
      client = instance_double('Mongo::Client', write_concern: nil)
      allow(Mongo::Client).to receive(:new).and_return(client)

      expect(described_class.build_session(['127.0.0.1:27017'], {})).to be(client)
    end

  end

end
