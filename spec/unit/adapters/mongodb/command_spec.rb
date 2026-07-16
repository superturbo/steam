require 'spec_helper'

require_relative '../../../../lib/locomotive/steam/adapters/mongodb.rb'

describe Locomotive::Steam::Adapters::MongoDB::Command do

  let(:site)        { instance_double('Site', _id: 42) }
  let(:scope)       { instance_double('Scope', site: site) }
  let(:collection)  { instance_double('Mongo::Collection') }
  let(:mapper)      { instance_double('Mapper') }
  let(:entity)      { { _id: 7, views: 1 } }

  let(:command)     { described_class.new(collection, mapper, scope) }

  before do
    allow(collection).to receive(:update_one)
    allow(collection).to receive(:delete_one)
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

    it 'issues a tenant-scoped $inc update' do
      subject
      expect(collection).to have_received(:update_one).with({ _id: 7, site_id: 42 }, '$inc' => { views: 3 })
    end

    it 'bumps the attribute on the entity and returns it' do
      expect(subject).to be(entity)
      expect(entity[:views]).to eq 4
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
