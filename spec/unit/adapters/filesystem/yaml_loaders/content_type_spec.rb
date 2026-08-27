require 'spec_helper'

require 'tmpdir'
require 'fileutils'

require_relative '../../../../../lib/locomotive/steam/adapters/filesystem/yaml_loader.rb'
require_relative '../../../../../lib/locomotive/steam/adapters/filesystem/yaml_loaders/content_type.rb'

describe Locomotive::Steam::Adapters::Filesystem::YAMLLoaders::ContentType do

  let(:site_path) { default_fixture_site_path }
  let(:loader)    { described_class.new(site_path) }
  let(:scope)     { instance_double('Scope', locale: :en) }

  def load_fields(definition)
    Dir.mktmpdir do |dir|
      types_path = File.join(dir, 'app', 'content_types')
      FileUtils.mkdir_p(types_path)
      File.write(File.join(types_path, 'articles.yml'), definition)

      described_class.new(dir).load(scope).first[:entries_custom_fields]
    end
  end

  describe '#load' do

    subject { loader.load(scope).sort { |a, b| a[:slug] <=> b[:slug] } }

    it 'tests various stuff' do
      expect(subject.size).to eq 6
      expect(subject[1][:slug]).to eq('bands')
      expect(subject[1][:entries_custom_fields].size).to eq 5
      expect(subject[1][:entries_custom_fields].first[:position]).to eq 0
    end

  end

  describe 'the capability model at load' do

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

  describe 'the field namespace at load' do

    %w(id _id _slug _label _visible _position site_id content_type_id
       content_type_slug content_type site created_at updated_at
       seo_title meta_description meta_keywords _class_name
       _password_field _auth_reset_token _auth_reset_sent_at
       _permalink _translated errors next previous).each do |name|
      it "refuses a field named #{name}" do
        expect do
          load_fields(<<~YAML)
            fields:
            - #{name}:
                type: string
          YAML
        end.to raise_error(Locomotive::Steam::UnsupportedSchemaError,
                           /articles\.yml, field #{name}: #{name} is a reserved name/) do |error|
          expect(error.reason).to eq :reserved_field_name
        end
      end
    end

    it 'refuses a name starting with an underscore' do
      expect do
        load_fields(<<~YAML)
          fields:
          - _highlight:
              type: string
        YAML
      end.to raise_error(Locomotive::Steam::UnsupportedSchemaError,
                         /articles\.yml, field _highlight: _highlight is a reserved name/) do |error|
        expect(error.reason).to eq :reserved_field_name
      end
    end

    it 'refuses a name starting with position_in_' do
      expect do
        load_fields(<<~YAML)
          fields:
          - position_in_author:
              type: integer
        YAML
      end.to raise_error(Locomotive::Steam::UnsupportedSchemaError,
                         /articles\.yml, field position_in_author: position_in_author is a reserved name/) do |error|
        expect(error.reason).to eq :reserved_field_name
      end
    end

    it 'refuses a field named after the name an association answers to, whatever the order' do
      forward = <<~YAML
        fields:
        - maker:
            type: belongs_to
            class_name: makers
        - maker_id:
            type: string
      YAML
      backward = <<~YAML
        fields:
        - maker_id:
            type: string
        - maker:
            type: belongs_to
            class_name: makers
      YAML

      [forward, backward].each do |definition|
        expect { load_fields(definition) }
          .to raise_error(Locomotive::Steam::UnsupportedSchemaError,
                          /articles\.yml: fields maker and maker_id share the entry name maker_id/) do |error|
          expect(error.reason).to eq :colliding_field_name
        end
      end
    end

    it 'refuses a field named after the name a select answers to' do
      expect do
        load_fields(<<~YAML)
          fields:
          - category:
              type: select
          - category_id:
              type: string
        YAML
      end.to raise_error(Locomotive::Steam::UnsupportedSchemaError,
                         /articles\.yml: fields category and category_id share the entry name category_id/)
    end

    it 'refuses a field named after the name a many_to_many answers to' do
      expect do
        load_fields(<<~YAML)
          fields:
          - topics:
              type: many_to_many
              class_name: topics
          - topic_ids:
              type: string
        YAML
      end.to raise_error(Locomotive::Steam::UnsupportedSchemaError,
                         /articles\.yml: fields topic_ids and topics share the entry name topic_ids/)
    end

    it 'refuses two fields answering to one derived name' do
      expect do
        load_fields(<<~YAML)
          fields:
          - categories:
              type: many_to_many
              class_name: categories
          - category:
              type: many_to_many
              class_name: categories
        YAML
      end.to raise_error(Locomotive::Steam::UnsupportedSchemaError,
                         /articles\.yml: fields categories and category share the entry name category_ids/) do |error|
        expect(error.reason).to eq :colliding_field_name
      end
    end

    it 'refuses a field named after the confirmation a password answers to' do
      expect do
        load_fields(<<~YAML)
          fields:
          - secret:
              type: password
          - secret_confirmation:
              type: string
        YAML
      end.to raise_error(Locomotive::Steam::UnsupportedSchemaError,
                         /articles\.yml: fields secret and secret_confirmation share the entry name secret_confirmation/)
    end

    it 'names every owner of a shared entry name' do
      expect do
        load_fields(<<~YAML)
          fields:
          - people:
              type: many_to_many
              class_name: people
          - person:
              type: many_to_many
              class_name: people
          - person_ids:
              type: string
        YAML
      end.to raise_error(Locomotive::Steam::UnsupportedSchemaError,
                         /articles\.yml: fields people, person, and person_ids share the entry name person_ids/)
    end

    it 'refuses a name declared twice' do
      expect do
        load_fields(<<~YAML)
          fields:
          - rating:
              type: string
          - rating:
              type: text
        YAML
      end.to raise_error(Locomotive::Steam::UnsupportedSchemaError,
                         /articles\.yml, field rating: declared more than once/) do |error|
        expect(error.reason).to eq :colliding_field_name
      end
    end

    it 'refuses a field named after the size a file answers to' do
      expect do
        load_fields(<<~YAML)
          fields:
          - photo:
              type: file
          - photo_size:
              type: string
        YAML
      end.to raise_error(Locomotive::Steam::UnsupportedSchemaError,
                         /articles\.yml: fields photo and photo_size share the entry name photo_size/)
    end

    it 'refuses a field named after the url a file answers to' do
      expect do
        load_fields(<<~YAML)
          fields:
          - photo:
              type: file
          - photo_url:
              type: string
        YAML
      end.to raise_error(Locomotive::Steam::UnsupportedSchemaError,
                         /articles\.yml: fields photo and photo_url share the entry name photo_url/)
    end

    it 'refuses a field named after the hash a password answers to' do
      expect do
        load_fields(<<~YAML)
          fields:
          - secret:
              type: password
          - secret_hash:
              type: string
        YAML
      end.to raise_error(Locomotive::Steam::UnsupportedSchemaError,
                         /articles\.yml: fields secret and secret_hash share the entry name secret_hash/)
    end

    it 'keeps distinct names apart' do
      fields = load_fields(<<~YAML)
        fields:
        - maker:
            type: belongs_to
            class_name: makers
        - maker_name:
            type: string
      YAML

      expect(fields.map { |field| field[:name] }).to eq %w(maker maker_name)
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
