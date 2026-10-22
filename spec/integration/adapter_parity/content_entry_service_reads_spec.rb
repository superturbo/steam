require 'spec_helper'

require_relative '../../../lib/locomotive/steam/adapters/filesystem.rb'
require_relative '../../../lib/locomotive/steam/adapters/mongodb.rb'
require_relative '../../support/adapter_parity_fixture'
require_relative '../../support/adapter_parity_context'

describe 'Adapter parity' do

  shared_examples_for 'the adapter parity dataset' do

    include_context 'adapter parity dataset access'

    describe 'the content entry service' do

      include_context 'adapter parity service access'

      it 'lists what a type holds, and narrows it by conditions' do
        expect(service.all('specimens').size).to eq 6
        expect(service.all('specimens', flag: false).size).to eq 3
      end

      it 'lists as json' do
        entry = service.all('specimens', { flag: true }, true).first

        expect(entry.slice('name', 'score')).to eq('name' => 'Scalars', 'score' => 5)
      end

      # Filesystem IDs are slugs, so only MongoDB exercises the ID fallback.
      it 'finds an entry by its slug and by the id its store issued' do
        scalars = service.find('specimens', 'scalars')

        expect(scalars.name).to eq 'Scalars'
        expect(service.find('specimens', scalars._id).name).to eq 'Scalars'
      end

      it 'finds an entry whose slug spells an object id' do
        expect(service.find('makers', '0123456789abcdef01234567').name).to eq 'Hex slug'
      end

      it 'finds no hidden entry, by its slug or its id' do
        hidden = specimens.all(_slug: 'hidden', _visible: nil).first

        expect([service.find('specimens', 'hidden'), service.find('specimens', hidden._id)]).to eq [nil, nil]
      end

      describe 'given a blank identifier' do

        include_context 'adapter parity service writing'

        let!(:slugless) do
          created    = service.create('submissions', valid)
          repository = entries_of('submissions')

          repository.find(created._id).tap do |entry|
            entry[:_slug] = nil
            repository.update(entry)
          end
        end

        [nil, '', '  '].each do |blank|

          it "finds no entry for #{blank.inspect}, though an entry has no slug" do
            expect(service.find('submissions', blank)).to be_nil
          end

        end

        it 'hands findEntry no entry for a null id' do
          context = ::Liquid::Context.new({}, {}, { session: {}, cookies: {} })
          actions = Locomotive::Steam::ActionService.new(instance_double('Site', as_json: {}), nil, content_entry: service)

          expect(actions.run("return findEntry('submissions', null);", {}, context)).to be_nil
        end

      end

    end

  end

  context 'MongoDB' do

    before(:all) { AdapterParityFixture.seed_mongodb! }
    after(:all)  { AdapterParityFixture.cleanup! }

    it_should_behave_like 'the adapter parity dataset' do
      let(:adapter)  { AdapterParityFixture.mongodb_adapter }

      def filesystem?; false; end
    end

  end

  context 'Filesystem' do

    it_should_behave_like 'the adapter parity dataset' do
      let(:adapter) { AdapterParityFixture.filesystem_adapter }

      def filesystem?; true; end
    end

  end

end
