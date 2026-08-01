require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'

describe Locomotive::Steam::ContentEntryRepository do

  shared_examples_for 'a writable repository' do

    let(:site)              { Locomotive::Steam::Site.new(_id: site_id, locales: %w(en fr nb)) }
    let(:locale)            { :en }
    let(:type_repository)   { Locomotive::Steam::ContentTypeRepository.new(adapter, site, locale) }
    let(:repository)        { described_class.new(adapter, site, locale, type_repository).with(type) }
    let(:type)              { type_repository.by_slug('bands') }
    let(:target_type)       { type_repository.by_slug('songs') }

    describe '#create' do

      let(:attributes) { { title: 'Jeremy', band_id: 'pearl-jam', short_description: '"Jeremy" is a song by the American rock band Pearl Jam' } }
      let(:entry) { repository.with(target_type).build(attributes) }

      subject { repository.create(entry) }

      it { expect { subject }.to change { repository.all.size } }
      it { expect(subject._id).not_to eq nil }

      after { repository.delete(entry) }

    end

    describe '#inc' do

      let(:type) { type_repository.by_slug('songs') }
      let(:attributes) { { title: 'Jeremy', band_id: 'pearl-jam', short_description: '"Jeremy" is a song by the American rock band Pearl Jam', views: 41 } }
      let(:entry) { repository.with(type).build(attributes) }

      before { repository.create(entry) }

      subject { repository.inc(entry, :views) }

      it { expect(subject.views).to eq 42 }

      after { repository.delete(entry) }

    end

  end

  context 'MongoDB' do

    it_should_behave_like 'a writable repository' do

      let(:site_id)   { mongodb_site_id }
      let(:adapter)   { Locomotive::Steam::MongoDBAdapter.new(database: mongodb_database, hosts: ['127.0.0.1:27017']) }

    end

  end

  context 'Filesystem' do

    it_should_behave_like 'a writable repository' do

      let(:site_id)   { 1 }
      let(:adapter)   { Locomotive::Steam::FilesystemAdapter.new(default_fixture_site_path) }

      after(:all) { Locomotive::Steam::Adapters::Filesystem::SimpleCacheStore.new.clear }

      describe '#create' do
        let(:messages)  { type_repository.by_slug('messages') }
        let(:message)   { repository.with(messages).build(name: 'John', email: 'john@doe.net', message: 'Hello world!') }
        subject { repository.create(message) }
        it { expect { subject }.to change { repository.all.size } }
      end

      describe '#delete' do
        let(:messages) { type_repository.by_slug('messages') }
        let(:message)  { repository.with(messages).build(name: 'Jane', email: 'jane@doe.net', message: 'Bye!') }
        before { repository.create(message) }
        subject { repository.delete(message) }

        it 'removes the entry from later queries' do
          expect { subject }.to change { repository.all.size }.by(-1)
        end
      end

      describe '#update' do
        let(:detached_entry) do
          repository.find('pearl-jam').dup.tap do |entity|
            entity.attributes = entity.attributes.dup
            entity[:leader] = 'Vedder'
          end
        end

        before { repository.update(detached_entry) }

        it 'is visible to a later query' do
          expect(repository.find('pearl-jam').leader).to eq 'Vedder'
        end
      end

    end

  end

end
