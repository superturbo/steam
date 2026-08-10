require 'spec_helper'

require_relative '../../../../lib/locomotive/steam/adapters/mongodb.rb'

describe Locomotive::Steam::Adapters::MongoDB::Command do

  let(:site)        { instance_double('Site', _id: 42) }
  let(:scope)       { instance_double('Scope', site: site) }
  let(:collection)  { instance_double('Mongo::Collection', name: 'posts') }
  let(:mapper)      { instance_double('Mapper') }
  let(:entity)      { { _id: 7, views: 1 } }

  let(:command)     { described_class.new(collection, mapper, scope) }

  before do
    allow(collection).to receive(:update_one)
    allow(collection).to receive(:delete_one)
    allow(collection).to receive(:find_one_and_update).and_return({ _id: 7, views: 4 })
    allow(mapper).to receive(:serialize).and_return({ name: 'Hello' })

    def entity._id; self[:_id]; end
  end

  describe '#update' do

    subject { command.update(entity) }

    it 'issues a tenant-scoped $set update' do
      subject
      expect(collection).to have_received(:update_one).with({ _id: 7, site_id: 42 }, '$set' => { name: 'Hello' })
    end

    it { is_expected.to be(entity) }

    context 'when the scope has no site (unscoped repository, e.g. SiteRepository)' do
      let(:site) { nil }

      it 'scopes the write by _id alone' do
        subject
        expect(collection).to have_received(:update_one).with({ _id: 7 }, '$set' => { name: 'Hello' })
      end
    end

  end

  describe '#inc' do

    subject { command.inc(entity, :views, 3) }

    it 'asks the server to check the type and the room before it writes' do
      subject

      expect(collection).to have_received(:find_one_and_update).with(
        { _id: 7, site_id: 42,
          '$or' => [
            { views: { '$exists' => false } },
            { views: { '$type' => %w(int long), '$gte' => -2**63, '$lte' => 2**63 - 4 } }
          ] },
        { '$inc' => { views: 3 }, '$set' => { 'updated_at' => kind_of(Time) } },
        return_document: :after, projection: { views: 1 }
      )
    end

    it 'takes the attribute from the answer, not from its own arithmetic' do
      allow(collection).to receive(:find_one_and_update).and_return({ _id: 7, views: 51 })

      expect(subject).to be(entity)
      expect(entity[:views]).to eq 51
    end

    it 'refuses an increment the entry has no room for' do
      allow(collection).to receive(:find_one_and_update).and_return(nil)
      allow(collection).to receive(:find).and_return(double('view', limit: [{ _id: 7 }]))

      expect { subject }
        .to raise_error(Locomotive::Steam::InvalidIncrement, 'views cannot be incremented by 3')
    end

    it 'reports an entry that is no longer there' do
      allow(collection).to receive(:find_one_and_update).and_return(nil)
      allow(collection).to receive(:find).and_return(double('view', limit: []))

      expect { subject }
        .to raise_error(Locomotive::Steam::Models::Repository::RecordNotFound)
    end

    it 'leaves a failure it did not ask about alone' do
      allow(collection).to receive(:find_one_and_update)
        .and_raise(Mongo::Error::OperationFailure.new('not authorized'))

      expect { subject }.to raise_error(Mongo::Error::OperationFailure)
    end

  end

  describe '#delete' do

    subject { command.delete(entity) }

    it 'issues a tenant-scoped delete' do
      subject
      expect(collection).to have_received(:delete_one).with(_id: 7, site_id: 42)
    end

    context 'when the scope has no site' do
      let(:site) { nil }

      it 'scopes the delete by _id alone' do
        subject
        expect(collection).to have_received(:delete_one).with(_id: 7)
      end
    end

  end

end
