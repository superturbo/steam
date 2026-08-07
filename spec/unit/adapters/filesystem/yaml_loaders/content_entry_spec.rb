require 'spec_helper'

require_relative '../../../../../lib/locomotive/steam/adapters/filesystem/yaml_loader.rb'
require_relative '../../../../../lib/locomotive/steam/adapters/filesystem/yaml_loaders/content_entry.rb'

describe Locomotive::Steam::Adapters::Filesystem::YAMLLoaders::ContentEntry do

  let(:site_path)     { default_fixture_site_path }
  let(:content_type)  { instance_double('Bands', _id: 42, slug: 'bands', association_fields: [], select_fields: [], file_fields: [], password_fields: [], fields_by_name: {}) }
  let(:scope)         { instance_double('Scope', locale: :en, site: nil, context: { content_type: content_type }) }
  let(:loader)        { described_class.new(site_path) }

  describe '#load' do

    subject { loader.load(scope).sort { |a, b| a[:_label] <=> b[:_label] } }

    it 'tests various stuff' do
      expect(subject.size).to eq 3
      expect(subject.first[:_label]).to eq 'Alice in Chains'
      expect(subject.first[:content_type]).to eq nil
    end

    context 'two entries spelling out the same slug' do

      let(:entries) do
        [{ 'Pearl Jam' => { '_slug' => 'seattle' } }, { 'Soundgarden' => { '_slug' => 'seattle' } }]
      end

      before { allow(loader).to receive(:_load).and_return(HashConverter.to_sym(entries)) }

      it 'says which file and which entries' do
        expect { subject }
          .to raise_error(%r{data/bands\.yml, entries Pearl Jam and Soundgarden: duplicate slug "seattle"})
      end

      context 'in one locale of many' do

        let(:entries) do
          [{ 'Pearl Jam'   => { '_slug' => { 'en' => 'seattle', 'fr' => 'seattle-fr' } } },
           { 'Soundgarden' => { '_slug' => { 'en' => 'soundgarden', 'fr' => 'seattle-fr' } } }]
        end

        it 'says which locale as well' do
          expect { subject }.to raise_error(/locale fr, duplicate slug "seattle-fr"/)
        end

      end

      context 'one of them spelling it out for every locale' do

        let(:entries) do
          [{ 'Pearl Jam'   => { '_slug' => 'seattle' } },
           { 'Soundgarden' => { '_slug' => { 'en' => 'seattle', 'fr' => 'soundgarden' } } }]
        end

        it { expect { subject }.to raise_error(/locale en, duplicate slug "seattle"/) }

      end

    end

    context 'two entries each spelling out a slug of their own' do

      before { allow(loader).to receive(:_load).and_return(HashConverter.to_sym(entries)) }

      context 'the same one, in a locale of their own' do

        let(:entries) do
          [{ 'Pearl Jam'   => { '_slug' => { 'en' => 'seattle', 'fr' => 'pearl-jam' } } },
           { 'Soundgarden' => { '_slug' => { 'en' => 'soundgarden', 'fr' => 'seattle' } } }]
        end

        it { expect { subject }.not_to raise_error }

      end

      context 'both leaving the same locale empty' do

        let(:entries) do
          [{ 'Pearl Jam'   => { '_slug' => { 'en' => '', 'fr' => 'pearl-jam' } } },
           { 'Soundgarden' => { '_slug' => { 'en' => '', 'fr' => 'soundgarden' } } }]
        end

        it { expect { subject }.to raise_error(/locale en, duplicate slug ""/) }

      end

      context 'spelling out none at all' do

        let(:entries) { [{ 'Pearl Jam' => { '_slug' => '' } }, { 'Soundgarden' => { '_slug' => '' } }] }

        it { expect { subject }.not_to raise_error }

      end

    end

    context 'a content type with a belongs_to field' do

      let(:field)         { instance_double('Field', name: 'band', type: :belongs_to) }
      let(:content_type)  { instance_double('Songs', slug: 'songs', association_fields: [field], select_fields: [], file_fields: [], password_fields: [], fields_by_name: {}) }

      it 'adds a new attribute for the foreign key' do
        expect(subject.first[:band_id]).to eq 'pearl-jam'
        expect(subject.first[:band]).to eq nil
        expect(subject.first[:position_in_band]).to eq 0
      end

      context 'the entry carries an explicit position' do

        before do
          allow(loader).to receive(:_load).and_return([{ 'One' => { band: 'pearl-jam', position_in_band: 5 } }])
        end

        it 'keeps the explicit position_in_<name> over the file order' do
          expect(subject.first[:position_in_band]).to eq 5
        end

      end

      context 'the explicit position is zero' do

        before do
          allow(loader).to receive(:_load).and_return([
            { 'One' => { band: 'pearl-jam' } },
            { 'Two' => { band: 'pearl-jam', position_in_band: 0 } }
          ])
        end

        it 'keeps the explicit zero over the file order' do
          expect(subject.last[:position_in_band]).to eq 0
        end

      end

    end

    context 'a content type with a select field' do

      let(:options)       { instance_double('Options') }
      let(:field)         { instance_double('Field', name: 'kind', type: :select, select_options: options) }
      let(:content_type)  { instance_double('Bands', slug: 'bands', select_fields: [field], association_fields: [], file_fields: [], password_fields: [], fields_by_name: {}) }

      it 'adds a new attribute for the foreign key' do
        expect(options).to receive(:by_name).twice.with('grunge').and_return(instance_double('GrungeOption', _id: 0))
        expect(options).to receive(:by_name).with('rock').and_return(instance_double('RockOption', _id: 1))
        expect(subject.first[:kind_id]).to eq 0
        expect(subject.first[:kind]).to eq nil
      end

    end

    context 'a content type with a password field' do

      let(:field)         { instance_double('Field', name: 'password', type: :password) }
      let(:content_type)  { instance_double('Accounts', slug: 'accounts', select_fields: [], association_fields: [], file_fields: [], password_fields: [field], fields_by_name: {}) }

      it 'adds a new attribute for the hashed password' do
        expect(subject.first[:password_hash]).not_to eq 'easyone'
        expect(subject.first[:password]).to eq nil
      end

    end

    context 'a content type with a localized field' do

      let(:options_scope) { instance_double('Scope', :locale= => true) }
      let(:options)       { instance_double('SelectOptionsRepository', scope: options_scope) }
      let(:field)         { instance_double('Field', name: 'category', type: :select, localized: true, select_options: options) }
      let(:content_type)  { instance_double('Updates', slug: 'updates', select_fields: [field], association_fields: [], file_fields: [], password_fields: [], fields_by_name: {}) }

      it 'adds a new localized attribute for the foreign key' do
        option = instance_double('Option', _id: 0)
        allow(options_scope).to receive(:with_locale) { |_, &block| block.call }
        allow(options).to receive(:by_name).with('General').and_return(option)
        allow(options).to receive(:by_name).with('Général').and_return(option)
        expect(subject.last[:category_id]).to eq({ en: 0, fr: 0 })
        expect(subject.last[:category]).to eq nil
      end

    end

    context 'a content type with a value the field keeps differently' do

      let(:field)         { instance_double('Field', name: 'featured', type: :boolean,
                                                     localized?: false, persisted_name: 'featured') }
      let(:content_type)  { instance_double('Bands', slug: 'bands', select_fields: [], association_fields: [],
                                                     file_fields: [], password_fields: [],
                                                     fields_by_name: { featured: field }) }

      it 'reads it as the value the field keeps' do
        expect(subject.map { |entry| entry[:featured] }).to eq [false, false, true]
      end

      context 'the field cannot read' do

        before do
          allow(Locomotive::Steam::ContentFieldValues).to receive(:normalize_input)
            .and_raise(Locomotive::Steam::ContentFieldValues::ParseError.new(:wrong_type, 'expected a boolean'))
        end

        it 'says which file, which entry and which field' do
          expect { subject }.to raise_error(/bands\.yml, entry Pearl Jam, field featured: expected a boolean/)
        end

        it 'keeps the reason the grammar gave' do
          expect { subject }.to raise_error(Locomotive::Steam::ContentFieldValues::ParseError) do |error|
            expect(error.reason).to eq :wrong_type
          end
        end

        context 'in one locale of many' do

          let(:field)         { instance_double('Field', name: 'text', type: :string,
                                                         localized?: true, persisted_name: 'text') }
          let(:content_type)  { instance_double('Updates', slug: 'updates', select_fields: [], association_fields: [],
                                                           file_fields: [], password_fields: [],
                                                           fields_by_name: { text: field }) }

          before do
            allow(Locomotive::Steam::ContentFieldValues).to receive(:normalize_input) do |_type, value, _site|
              if value == 'phrase FR'
                raise Locomotive::Steam::ContentFieldValues::ParseError.new(:invalid_encoding, 'expected text')
              end

              value
            end
          end

          it 'says which locale as well' do
            expect { subject }.to raise_error(/field text: locale fr, expected text/)
          end

          it 'keeps the reason the grammar gave' do
            expect { subject }.to raise_error(Locomotive::Steam::ContentFieldValues::ParseError) do |error|
              expect(error.reason).to eq :invalid_encoding
            end
          end

        end

      end

    end

    context 'a content type with a file field' do

      let(:field)         { instance_double('Field', name: 'cover', type: :file) }
      let(:content_type)  { instance_double('Songs', slug: 'songs', select_fields: [], association_fields: [], file_fields: [field], password_fields: [], fields_by_name: {}) }

      it 'stores the size of the file' do
        expect(subject.first[:cover_size]).to eq('default' => 14768)
      end

      it 'stores the size of the file in multiple locales' do
        expect(subject[1][:cover_size]).to eq('en' => 14768, 'fr' => 165883, 'nb' => 165883)
      end


    end

  end

end
