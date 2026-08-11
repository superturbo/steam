require 'spec_helper'

require 'tmpdir'
require 'fileutils'

require_relative '../../../../../lib/locomotive/steam/adapters/filesystem/yaml_loader.rb'
require_relative '../../../../../lib/locomotive/steam/adapters/filesystem/yaml_loaders/content_type.rb'

describe Locomotive::Steam::Adapters::Filesystem::YAMLLoaders::ContentType do

  let(:site_path) { default_fixture_site_path }
  let(:loader)    { described_class.new(site_path) }

  describe '#load' do

    let(:scope) { instance_double('Scope', locale: :en) }

    subject { loader.load(scope).sort { |a, b| a[:slug] <=> b[:slug] } }

    it 'tests various stuff' do
      expect(subject.size).to eq 6
      expect(subject[1][:slug]).to eq('bands')
      expect(subject[1][:entries_custom_fields].size).to eq 5
      expect(subject[1][:entries_custom_fields].first[:position]).to eq 0
    end

  end

  describe 'the capability model at load' do

    let(:scope) { instance_double('Scope', locale: :en) }

    def load_fields(definition)
      Dir.mktmpdir do |dir|
        types_path = File.join(dir, 'app', 'content_types')
        FileUtils.mkdir_p(types_path)
        File.write(File.join(types_path, 'articles.yml'), definition)

        described_class.new(dir).load(scope).first[:entries_custom_fields]
      end
    end

    it 'refuses a localized field of a type that cannot be localized' do
      %w(belongs_to has_many many_to_many password).each do |type|
        expect do
          load_fields(<<~YAML)
            fields:
            - author:
                type: #{type}
                localized: true
          YAML
        end.to raise_error(Locomotive::Steam::UnsupportedSchemaError,
                           /articles\.yml, field author: a #{type} field cannot be localized/) do |error|
          expect(error.reason).to eq :unsupported_localization
        end
      end
    end

    it 'refuses a required field of a type that cannot be required' do
      %w(tags password).each do |type|
        expect do
          load_fields(<<~YAML)
            fields:
            - author:
                type: #{type}
                required: true
          YAML
        end.to raise_error(Locomotive::Steam::UnsupportedSchemaError,
                           /articles\.yml, field author: a #{type} field cannot be required/) do |error|
          expect(error.reason).to eq :unsupported_required
        end
      end
    end

    it 'refuses an unknown field type, naming it' do
      expect do
        load_fields(<<~YAML)
          fields:
          - author:
              type: money
        YAML
      end.to raise_error(Locomotive::Steam::UnsupportedSchemaError,
                         /articles\.yml, field author: unknown field type "money"/) do |error|
        expect(error.reason).to eq :unknown_field_type
      end
    end

    it 'keeps a legal declaration as written' do
      fields = load_fields(<<~YAML)
        fields:
        - title:
            type: string
            localized: true
      YAML

      expect(fields.first[:localized]).to eq true
    end

    it 'does not add a localized flag the source never spelled' do
      fields = load_fields(<<~YAML)
        fields:
        - author:
            type: belongs_to
            class_name: makers
      YAML

      expect(fields.first).not_to have_key(:localized)
    end

  end

  describe '#build_select_options_from_hash' do

    let(:options) { { en: ['General', 'Gigs', 'Bands'], fr: ['Général', 'Concerts', 'Groupes'] } }

    subject { loader.send(:build_select_options_from_hash, options) }

    it { is_expected.to eq [
      { _id: '0', name: { en: 'General', fr: 'Général' }, position: 0 },
      { _id: '1', name: { en: 'Gigs', fr: 'Concerts' }, position: 1 },
      { _id: '2', name: { en: 'Bands', fr: 'Groupes' }, position: 2 }]
    }

  end

  describe '#build_select_options_from_array' do

    # let(:options) { { en: ['General', 'Gigs', 'Bands'], fr: ['Général', 'Concerts', 'Groupes'] } }
    let(:options) { [{ en: 'General', fr: 'Général' }, { en: 'Gigs', fr: 'Concerts'}, { en: 'Bands', fr: 'Groupes' }] }

    subject { loader.send(:build_select_options_from_array, options) }

    it { is_expected.to eq [{ _id: 0, name: { en: 'General', fr: 'Général' }, position: 0 }, { _id: 1, name: { en: 'Gigs', fr: 'Concerts' }, position: 1 }, { _id: 2, name: { en: 'Bands', fr: 'Groupes' }, position: 2 }] }

  end

end
