require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'
require_relative '../../support/examples/adapter_contract'

describe Locomotive::Steam::MongoDBAdapter do

  let(:adapter) { described_class.new(nil) }

  it_behaves_like 'a repository adapter'

  describe '#key' do

    subject { adapter.key(:title, :in) }

    it { is_expected.to eq 'title.in' }

    it 'raises on an unknown operator' do
      expect { adapter.key(:title, :bogus) }.to raise_error(Locomotive::Steam::Adapters::Query::UnsupportedOperator)
    end

  end

  describe '#make_id' do

    let(:id) { '56fd9f48a2f42217744a85d7' }

    subject { adapter.make_id(id) }

    it { is_expected.to eq(BSON::ObjectId.from_string('56fd9f48a2f42217744a85d7')) }

    context 'passing a BSON::ObjectId' do

      let(:id) { BSON::ObjectId.from_string('56fd9f48a2f42217744a85d7') }

      it { is_expected.to eq id }

    end

    context 'passing an invalid id' do

      let(:id) { 'not-an-object-id' }

      it { is_expected.to eq false }

    end

  end

  describe '#count' do

    let(:site)       { instance_double('Site', _id: 42) }
    let(:scope)      { instance_double('Scope', locale: :en, site: site) }
    let(:mapper)     { instance_double('Mapper', name: :pages, localized_attributes: []) }
    let(:collection) { instance_double('Mongo::Collection') }
    let(:view)       { instance_double('Mongo::Collection::View') }

    before do
      allow(adapter).to receive(:collection).with(mapper).and_return(collection)
      allow(collection).to receive(:find).and_return(view)
      allow(view).to receive(:count_documents).and_return(7)
    end

    subject { adapter.count(mapper, scope) { where(published: true) } }

    it 'counts through count_documents on the tenant-scoped view' do
      expect(subject).to eq 7
      expect(collection).to have_received(:find).with(
        { '$and' => [{ 'published' => true }, { 'site_id' => 42 }] }, {}
      )
      expect(view).to have_received(:count_documents)
    end

  end

end
