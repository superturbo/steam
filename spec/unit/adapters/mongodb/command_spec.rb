require 'spec_helper'

require_relative '../../../../lib/locomotive/steam/adapters/mongodb.rb'

describe Locomotive::Steam::Adapters::MongoDB::Command do

  let(:site)        { instance_double('Site', _id: 42) }
  let(:scope)       { instance_double('Scope', site: site) }
  let(:collection)  { instance_double('Mongo::Collection') }
  let(:view)        { instance_double('Mongo::Collection::View') }
  let(:mapper)      { instance_double('Mapper') }
  let(:entity)      { { _id: 7, views: 1 } }

  let(:command)     { described_class.new(collection, mapper, scope) }

  before do
    allow(collection).to receive(:find).and_return(view)
    allow(view).to receive(:update_one)
    allow(view).to receive(:delete_one)
    allow(mapper).to receive(:serialize).and_return({ name: 'Hello' })

    def entity._id;  self[:_id]; end
  end

  describe 'tenant-scoped write filters' do

    describe '#update' do
      before { command.update(entity) }
      it { expect(collection).to have_received(:find).with(_id: 7, site_id: 42) }
    end

    describe '#delete' do
      before { command.delete(entity) }
      it { expect(collection).to have_received(:find).with(_id: 7, site_id: 42) }
    end

    describe '#inc' do
      before { command.inc(entity, :views, 3) }
      it { expect(collection).to have_received(:find).with(_id: 7, site_id: 42) }
    end

    context 'when the scope has no site (unscoped repository, e.g. SiteRepository)' do

      let(:site) { nil }

      describe '#update' do
        before { command.update(entity) }
        it { expect(collection).to have_received(:find).with(_id: 7) }
      end

    end

  end

end
