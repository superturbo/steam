require 'spec_helper'

require_relative '../../../../../lib/locomotive/steam/adapters/filesystem/yaml_loader.rb'
require_relative '../../../../../lib/locomotive/steam/adapters/filesystem/yaml_loaders/content_entry.rb'

describe Locomotive::Steam::Adapters::Filesystem::YAMLLoaders::ContentEntry do

  let(:site_path)     { default_fixture_site_path }
  let(:content_type)  { instance_double('Bands', _id: 42, slug: 'bands', association_fields: [], select_fields: [], file_fields: [], password_fields: [], fields_by_name: {}) }
  let(:scope)         { instance_double('Scope', locale: :en, default_locale: :en, site: nil, context: { content_type: content_type }) }
  let(:loader)        { described_class.new(site_path) }

  describe '#load' do

    subject { loader.load(scope).sort { |a, b| a[:_label] <=> b[:_label] } }

    it 'tests various stuff' do
      expect(subject.size).to eq 3
      expect(subject.first[:_label]).to eq 'Alice in Chains'
      expect(subject.first[:content_type]).to eq nil
    end

    context 'the file order is the position' do

      let(:entries) do
        [{ 'First' => { 'name' => 'a' } }, { 'Second' => { 'name' => 'b' } }, { 'Third' => { 'name' => 'c' } }]
      end

      before { allow(loader).to receive(:_load).and_return(HashConverter.to_sym(entries)) }

      it 'derives _position from the file index' do
        expect(loader.load(scope).map { |e| [e[:_label], e[:_position]] })
          .to eq [['First', 0], ['Second', 1], ['Third', 2]]
      end

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

      it 'adds a new attribute for the foreign key without inventing a position' do
        expect(subject.first[:band_id]).to eq 'pearl-jam'
        expect(subject.first[:band]).to eq nil
        expect(subject.first.key?(:position_in_band)).to be false
      end

      context 'a group spelling out its own order' do

        before do
          allow(loader).to receive(:_load).and_return(HashConverter.to_sym([
            { 'One' => { band: 'pearl-jam', position_in_band: 1 } },
            { 'Two' => { band: 'pearl-jam', position_in_band: 0 } },
            { 'Three' => { band: 'nirvana' } }
          ]))
        end

        it 'keeps the explicit positions and leaves the other group alone' do
          by_label = subject.index_by { |entry| entry[:_label] }

          expect(by_label['One'][:position_in_band]).to eq 1
          expect(by_label['Two'][:position_in_band]).to eq 0
          expect(by_label['Three'].key?(:position_in_band)).to be false
        end

      end

      context 'a full group on one of two belongs_to fields' do

        let(:venue) { instance_double('Field', name: 'venue', type: :belongs_to) }

        let(:content_type) do
          instance_double('Songs', slug: 'songs', association_fields: [field, venue],
                          select_fields: [], file_fields: [], password_fields: [], fields_by_name: {})
        end

        before do
          allow(loader).to receive(:_load).and_return(HashConverter.to_sym([
            { 'One' => { band: 'pearl-jam', position_in_band: 1, venue: 'roskilde' } },
            { 'Two' => { band: 'pearl-jam', position_in_band: 0, venue: 'roskilde' } }
          ]))
        end

        it 'keeps the groups of the two associations independent' do
          by_label = subject.index_by { |entry| entry[:_label] }

          expect(by_label['One'][:position_in_band]).to eq 1
          expect(by_label['One'][:venue_id]).to eq 'roskilde'
          expect(by_label['One'].key?(:position_in_venue)).to be false
          expect(by_label['Two'].key?(:position_in_venue)).to be false
        end

      end

      context 'a group spelling out only part of its order' do

        before do
          allow(loader).to receive(:_load).and_return(HashConverter.to_sym([
            { 'One' => { band: 'pearl-jam' } },
            { 'Two' => { band: 'pearl-jam', position_in_band: 0 } }
          ]))
        end

        it 'refuses the partial group' do
          expect { subject }.to raise_error(
            Locomotive::Steam::InvalidEntriesFileError,
            %r{data/songs\.yml, entries of band pearl-jam: position_in_band must be set for every entry in the group}) do |error|
            expect(error.reason).to eq :partial_position_group
          end
        end

      end

      context 'a group repeating a position' do

        before do
          allow(loader).to receive(:_load).and_return(HashConverter.to_sym([
            { 'One' => { band: 'pearl-jam', position_in_band: 0 } },
            { 'Two' => { band: 'pearl-jam', position_in_band: 0 } }
          ]))
        end

        it 'refuses the duplicate' do
          expect { subject }.to raise_error(
            Locomotive::Steam::InvalidEntriesFileError,
            %r{data/songs\.yml, entries of band pearl-jam: duplicate position_in_band}) do |error|
            expect(error.reason).to eq :duplicate_position
          end
        end

      end

      context 'a position naming no belongs_to field' do

        before do
          allow(loader).to receive(:_load).and_return(HashConverter.to_sym([
            { 'One' => { band: 'pearl-jam', position_in_venue: 0 } }
          ]))
        end

        it 'refuses the unknown association' do
          expect { subject }.to raise_error(
            Locomotive::Steam::InvalidEntriesFileError,
            %r{data/songs\.yml, entry One: position_in_venue names no belongs_to field}) do |error|
            expect(error.reason).to eq :unknown_association
          end
        end

      end

      context 'a position on an entry that links nothing' do

        [{}, { band: nil }, { band: '' }].each do |link|
          it "refuses it when the association is #{link.inspect}" do
            allow(loader).to receive(:_load).and_return(HashConverter.to_sym([
              { 'One' => link.merge(position_in_band: 0) }
            ]))

            expect { subject }.to raise_error(
              Locomotive::Steam::InvalidEntriesFileError,
              %r{data/songs\.yml, entry One: position_in_band without a linked band}) do |error|
              expect(error.reason).to eq :unlinked_position
            end
          end
        end

      end

      context 'a group with unique non-contiguous positions' do

        before do
          allow(loader).to receive(:_load).and_return(HashConverter.to_sym([
            { 'One' => { band: 'pearl-jam', position_in_band: 5 } },
            { 'Two' => { band: 'pearl-jam', position_in_band: 2 } }
          ]))
        end

        it 'accepts the gapped positions' do
          by_label = subject.index_by { |entry| entry[:_label] }

          expect(by_label['One'][:position_in_band]).to eq 5
          expect(by_label['Two'][:position_in_band]).to eq 2
        end

      end

      context 'a position no order can read' do

        ['5', 5.5, -1, nil, 2**63].each do |bad|
          it "refuses #{bad.inspect}" do
            allow(loader).to receive(:_load).and_return(HashConverter.to_sym([
              { 'One' => { band: 'pearl-jam', position_in_band: bad } }
            ]))

            expect { subject }.to raise_error(
              Locomotive::Steam::InvalidEntriesFileError,
              %r{data/songs\.yml, entry One: position_in_band takes a non-negative 64-bit integer}) do |error|
              expect(error.reason).to eq :invalid_position
            end
          end
        end

      end

      context 'the entry never names the association' do

        before { allow(loader).to receive(:_load).and_return([{ 'One' => {} }]) }

        it 'leaves the foreign key and the position missing' do
          expect(subject.first.key?(:band_id)).to be false
          expect(subject.first.key?(:position_in_band)).to be false
        end

      end

      context 'the entry names the association with an explicit null' do

        before { allow(loader).to receive(:_load).and_return([{ 'One' => { band: nil } }]) }

        it 'keeps the null foreign key without inventing a position' do
          expect(subject.first.key?(:band_id)).to be true
          expect(subject.first[:band_id]).to be_nil
          expect(subject.first.key?(:position_in_band)).to be false
        end

      end

      context 'the entry names the association with a blank slug' do

        before { allow(loader).to receive(:_load).and_return([{ 'One' => { band: '' } }]) }

        it 'links nothing and invents no position' do
          expect(subject.first[:band_id]).to eq ''
          expect(subject.first.key?(:position_in_band)).to be false
        end

      end

    end

    context 'a content type with a many_to_many field' do

      let(:field)         { instance_double('Field', name: 'tags', type: :many_to_many) }
      let(:content_type)  { instance_double('Songs', slug: 'songs', association_fields: [field], select_fields: [], file_fields: [], password_fields: [], fields_by_name: {}) }

      before { allow(loader).to receive(:_load).and_return([{ 'One' => attributes }]) }

      context 'the entry never names the association' do

        let(:attributes) { {} }

        it 'leaves the ids missing' do
          expect(subject.first.key?(:tag_ids)).to be false
        end

      end

      context 'the entry names the association with an explicit null' do

        let(:attributes) { { tags: nil } }

        it 'keeps the null ids' do
          expect(subject.first.key?(:tag_ids)).to be true
          expect(subject.first[:tag_ids]).to be_nil
        end

      end

    end

    context 'a content type with a file field' do

      let(:field)         { instance_double('Field', name: 'photo', type: :file) }
      let(:content_type)  { instance_double('Bands', slug: 'bands', select_fields: [], association_fields: [], file_fields: [field], password_fields: [], fields_by_name: {}) }

      before { allow(loader).to receive(:_load).and_return([{ 'One' => {} }]) }

      it 'does not invent file metadata for a missing file' do
        expect(subject.first.key?(:photo_size)).to be false
      end

    end

    context 'a content type with a select field' do

      let(:options_scope) { instance_double('OptionsScope') }
      let(:options)       { instance_double('Options', scope: options_scope) }

      before { allow(options_scope).to receive(:with_locale) { |&block| block.call } }
      let(:field)         { instance_double('Field', name: 'kind', persisted_name: 'kind_id', type: :select, localized?: false, select_options: options) }
      let(:content_type)  { instance_double('Bands', slug: 'bands', select_fields: [field], association_fields: [], file_fields: [], password_fields: [], fields_by_name: {}) }

      it 'adds a new attribute for the foreign key' do
        expect(options).to receive(:by_name).twice.with('grunge').and_return(instance_double('GrungeOption', _id: 0))
        expect(options).to receive(:by_name).with('rock').and_return(instance_double('RockOption', _id: 1))
        expect(subject.first[:kind_id]).to eq 0
        expect(subject.first[:kind]).to eq nil
      end

      context 'the entry never names the select' do

        before { allow(loader).to receive(:_load).and_return([{ 'One' => {} }]) }

        it 'leaves the foreign key missing' do
          expect(subject.first.key?(:kind_id)).to be false
        end

      end

      context 'the entry names the select with an explicit null' do

        before { allow(loader).to receive(:_load).and_return([{ 'One' => { kind: nil } }]) }

        it 'keeps the null foreign key' do
          expect(subject.first.key?(:kind_id)).to be true
          expect(subject.first[:kind_id]).to be_nil
        end

      end

      context 'the entry spells a hash for a select that is not localized' do

        before { allow(loader).to receive(:_load).and_return([{ 'One' => { kind: { en: 'grunge' } } }]) }

        it 'raises instead of resolving locales the field does not have' do
          expect { subject }.to raise_error(Locomotive::Steam::ContentFieldValues::ParseError,
                                            /bands\.yml, entry One, field kind/) do |error|
            expect(error.reason).to eq :wrong_type
          end
        end

      end

      context 'the entry names an option no schema holds' do

        before do
          allow(loader).to receive(:_load).and_return([{ 'One' => { kind: 'bogus' } }])
          allow(options).to receive(:by_name).with('bogus').and_return(nil)
        end

        it 'raises with the file, entry and field spelled out' do
          expect { subject }.to raise_error(Locomotive::Steam::ContentFieldValues::ParseError,
                                            /bands\.yml, entry One, field kind/) do |error|
            expect(error.reason).to eq :unknown_select_option
          end
        end

      end

    end

    context 'a content type with a password field' do

      let(:field)         { instance_double('Field', name: 'password', type: :password) }
      let(:content_type)  { instance_double('Accounts', slug: 'accounts', select_fields: [], association_fields: [], file_fields: [], password_fields: [field], fields_by_name: {}) }

      it 'adds a new attribute for the hashed password' do
        expect(subject.first[:password_hash]).not_to eq 'easyone'
        expect(subject.first[:password]).to eq nil
      end

      context 'the entry never names the password' do

        before { allow(loader).to receive(:_load).and_return([{ 'One' => {} }]) }

        it 'leaves the hash missing' do
          expect(subject.first.key?(:password_hash)).to be false
        end

      end

      context 'the entry names the password with an explicit null' do

        before { allow(loader).to receive(:_load).and_return([{ 'One' => { password: nil } }]) }

        it 'keeps the null hash instead of hashing an empty secret' do
          expect(subject.first.key?(:password_hash)).to be true
          expect(subject.first[:password_hash]).to be_nil
        end

      end

    end

    context 'a content type with a localized field' do

      let(:options_scope) { instance_double('Scope', :locale= => true) }
      let(:options)       { instance_double('SelectOptionsRepository', scope: options_scope) }
      let(:field)         { instance_double('Field', name: 'category', persisted_name: 'category_id', type: :select, localized: true, localized?: true, select_options: options) }
      let(:content_type)  { instance_double('Updates', slug: 'updates', select_fields: [field], association_fields: [], file_fields: [], password_fields: [], fields_by_name: {}) }

      it 'adds a new localized attribute for the foreign key' do
        option = instance_double('Option', _id: 0)
        allow(options_scope).to receive(:with_locale) { |_, &block| block.call }
        allow(options).to receive(:by_name).with('General').and_return(option)
        allow(options).to receive(:by_name).with('Général').and_return(option)
        expect(subject.last[:category_id]).to eq({ en: 0, fr: 0 })
        expect(subject.last[:category]).to eq nil
      end

      context 'a name no locale holds' do

        before do
          allow(loader).to receive(:_load).and_return([{ 'One' => { category: { fr: 'inconnu' } } }])
          allow(options_scope).to receive(:with_locale) { |_, &block| block.call }
          allow(options).to receive(:by_name).with('inconnu').and_return(nil)
        end

        it 'raises naming the locale' do
          expect { subject }.to raise_error(Locomotive::Steam::ContentFieldValues::ParseError,
                                            /field category, locale fr/) do |error|
            expect(error.reason).to eq :unknown_select_option
          end
        end

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
