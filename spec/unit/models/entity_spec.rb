require 'spec_helper'

describe Locomotive::Steam::Models::Entity do

  let(:klass) { Class.new { include Locomotive::Steam::Models::Entity } }
  let(:title) { Locomotive::Steam::Models::I18nField.new(:title, 'en' => 'Hello') }
  let(:entity) do
    klass.new(name: +'Ada', title: title, labels: [+'one'],
              payload: { 'a' => [{ 'b' => +'deep' }] }, notes: notes)
  end
  let(:notes) { Locomotive::Steam::Models::I18nField.new(:notes, 'en' => { 'a' => +'deep' }) }

  describe '#__query_attribute__' do

    def read(name, locale = :en)
      entity.__query_attribute__(name, locale)
    end

    it 'reads a stored attribute' do
      expect(read(:name)).to eq [true, 'Ada']
    end

    it 'reads an absent attribute as missing' do
      expect(read(:unknown)).to eq [false, nil]
    end

    it 'reads a stored null as present' do
      entity[:flag] = nil

      expect(read(:flag)).to eq [true, nil]
    end

    it 'reads a localized attribute in the asked locale' do
      expect(read(:title)).to eq [true, 'Hello']
    end

    it 'reads a localized attribute missing the asked locale as absent' do
      expect(read(:title, :fr)).to eq [false, nil]
    end

    it 'never reads a Ruby method' do
      expect(read(:hash)).to eq [false, nil]
      expect(read(:method)).to eq [false, nil]
    end

    it 'reads a stored attribute that shadows a Ruby method' do
      entity['hash'] = 'stored'

      expect(read(:hash)).to eq [true, 'stored']
    end

    it 'leaves read_query_attribute free as a plain attribute name' do
      entity['read_query_attribute'] = 'stored'

      expect(entity.read_query_attribute).to eq 'stored'
      expect(read(:read_query_attribute)).to eq [true, 'stored']
    end

  end

  describe '#dup' do

    subject { entity.dup }

    it 'changes a plain attribute on its own' do
      subject[:name] = 'Grace'

      expect(entity.name).to eq 'Ada'
    end

    it 'changes text on its own' do
      subject.name << ' Lovelace'

      expect(entity.name).to eq 'Ada'
    end

    it 'changes a list on its own' do
      subject.labels << 'two'
      subject.labels.first << ' more'

      expect(entity.labels).to eq ['one']
    end

    it 'changes what is nested inside an object on its own' do
      subject.payload['a'].first['b'] << ' change'

      expect(entity.payload).to eq('a' => [{ 'b' => 'deep' }])
    end

    it 'changes what a locale holds on its own' do
      subject.notes[:en]['a'] << ' change'

      expect(entity.notes[:en]).to eq('a' => 'deep')
    end

    it 'changes a locale of a localized attribute on its own' do
      subject.title[:en] = 'Bonjour'

      expect(entity.title[:en]).to eq 'Hello'
    end

    context 'an entity that holds associations' do

      let(:repository_klass) { Class.new { def initialize(_adapter); end; attr_accessor :scope } }
      let(:association) do
        Locomotive::Steam::Models::BelongsToAssociation.new(repository_klass, nil, nil,
                                                            association_name: :maker)
      end

      before do
        entity.associations = { maker: association }
        entity[:maker] = association
        association.__attach__(entity)
      end

      it 'reads them through itself, not through the entity it came from' do
        expect(subject.associations[:maker].instance_variable_get(:@entity)).to be(subject)
      end

      it 'keeps the one the entity carries the same as the one it lists' do
        expect(subject[:maker]).to be(subject.associations[:maker])
      end

      it 'leaves the entity it came from attached to its own' do
        subject

        expect(association.instance_variable_get(:@entity)).to be(entity)
      end

    end

  end

end
