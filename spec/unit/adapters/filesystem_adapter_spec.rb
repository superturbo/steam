require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../support/examples/adapter_contract'

describe Locomotive::Steam::FilesystemAdapter do

  let(:mapper)  { instance_double('Mapper', name: :test) }
  let(:scope)   { instance_double('Scope', site: site, locale: nil, to_key: 'key') }
  let(:adapter) { Locomotive::Steam::FilesystemAdapter.new(nil) }

  it_behaves_like 'a repository adapter'

  describe '#key' do

    subject { adapter.key(:title, :in) }

    it { is_expected.to eq 'title.in' }

    it 'rejects unknown operators and dotted field names' do
      expect { adapter.key(:title, :bogus) }.to raise_error(Locomotive::Steam::Adapters::Query::UnsupportedOperator)
      expect { adapter.key('address.city', :in) }.to raise_error(Locomotive::Steam::Adapters::Query::InvalidValue)
    end

  end

  describe '#query' do

    let(:collection) { [OpenStruct.new(site_id: 42, name: 'Hello world')] }

    before do
      allow(mapper).to receive(:to_entity) { |arg| arg }
      allow(adapter).to receive(:collection).and_return(collection)
    end

    subject { adapter.query(mapper, scope) { where(name: 'Hello world') } }

    context 'not scoped by a site' do

      let(:site) { nil }
      it { expect(subject.first.name).to eq 'Hello world' }

    end

    context 'scoped by a site' do

      let(:site) { instance_double('Site', _id: 42) }
      it { expect(subject.first.name).to eq 'Hello world' }

      context 'unknown site id' do

        let(:site) { instance_double('Site', _id: 1) }
        it { expect(subject.first).to eq nil }

      end

    end

  end

  describe '#inc' do

    let(:mapper)     { instance_double('Mapper', name: :posts) }
    let(:site)       { instance_double('Site', _id: 1) }
    let(:stored)     { OpenStruct.new(_id: 1, name: 'My post', views: 50) }
    let(:collection) { [stored] }
    let(:entity)     { OpenStruct.new(_id: 1, name: 'stale copy', views: 41) }
    let(:cache_key)  { "#{scope.to_key}_#{mapper.name}" }

    before do
      adapter.cache.delete(cache_key)
      allow(mapper).to receive(:to_entity) { |arg| arg }
      allow(adapter).to receive(:collection).and_return(collection)
    end

    after { adapter.cache.delete(cache_key) }

    subject { adapter.inc(mapper, scope, entity, :views) }

    it 'increments from the stored value, not the passed entity' do
      expect(subject.views).to eq 51
    end

    it 'makes the increment visible to a later read' do
      subject
      expect(adapter.find(mapper, scope, 1).views).to eq 51
    end

    it 'increments only the given field, leaving the stored record otherwise intact' do
      subject
      expect(adapter.find(mapper, scope, 1).name).to eq 'My post'
    end

    it 'starts a field the record never set at zero' do
      expect(adapter.inc(mapper, scope, entity, :reads).reads).to eq 1
    end

    it 'refuses a stored value no store would increment' do
      stored.views = 'lots'

      expect { subject }.to raise_error(Locomotive::Steam::InvalidIncrement, 'views holds "lots"')
    end

    it 'refuses a stored null, which is not a field it may create' do
      stored.views = nil

      expect { subject }.to raise_error(Locomotive::Steam::InvalidIncrement, 'views holds nil')
    end

    it 'refuses a stored value with no room for the amount' do
      stored.views = 2**63 - 1

      expect { subject }.to raise_error(Locomotive::Steam::InvalidIncrement, 'views has no room for 1')
      expect(stored.views).to eq 2**63 - 1
    end

    describe 'by an amount different from 1' do

      subject { adapter.inc(mapper, scope, entity, :views, 3) }

      it { expect(subject.views).to eq 53 }

    end

    context 'an unknown record' do

      let(:entity) { OpenStruct.new(_id: 999, name: 'ghost', views: 7) }

      it 'raises RecordNotFound without mutating the passed entity' do
        expect { subject }.to raise_error(Locomotive::Steam::Models::Repository::RecordNotFound)
        expect(entity.views).to eq 7
      end

    end

  end

  describe '#make_id' do

    let(:id) { '42' }

    subject { adapter.make_id(id) }

    it { is_expected.to eq('42') }

  end

end
