require 'spec_helper'

describe 'referenced association serialization' do

  let(:adapter) { instance_double('Adapter') }
  let(:scope)   { Locomotive::Steam::Models::Scope.new(nil, :en) }
  let(:target)  { instance_double('Entity', _id: 42) }

  def association(klass, name, &block)
    klass.new(Locomotive::Steam::ContentEntryRepository, scope, adapter,
              { association_name: name }, &block)
  end

  def serialized(klass, name, attributes)
    attributes.with_indifferent_access.tap do |hash|
      association(klass, name).__serialize__(hash)
    end
  end

  describe Locomotive::Steam::Models::BelongsToAssociation do

    it 'leaves the stored id when the entry carries no association attribute' do
      expect(serialized(described_class, :maker, 'maker_id' => 7)).to eq('maker_id' => 7)
    end

    it 'reads the id of a target the entry materialized' do
      expect(serialized(described_class, :maker, 'maker' => target, 'maker_id' => 7))
        .to eq('maker_id' => 42)
    end

    it 'clears the id the entry spells out as null' do
      expect(serialized(described_class, :maker, 'maker' => nil, 'maker_id' => 7))
        .to eq('maker_id' => nil)
    end

    it 'does not configure the repository during serialization' do
      configured = false
      proxy      = association(described_class, :maker) { configured = true }

      proxy.__serialize__({ 'maker' => target }.with_indifferent_access)

      expect(configured).to eq false
    end

  end

  describe Locomotive::Steam::Models::ManyToManyAssociation do

    it 'leaves the stored ids when the entry carries no association attribute' do
      expect(serialized(described_class, :topics, 'topic_ids' => [7])).to eq('topic_ids' => [7])
    end

    it 'reads the ids of targets the entry materialized' do
      expect(serialized(described_class, :topics, 'topics' => [target], 'topic_ids' => [7]))
        .to eq('topic_ids' => [42])
    end

    it 'clears the ids the entry spells out as empty' do
      expect(serialized(described_class, :topics, 'topics' => [], 'topic_ids' => [7]))
        .to eq('topic_ids' => [])
    end

    it 'does not configure the repository during serialization' do
      configured = false
      proxy      = association(described_class, :topics) { configured = true }

      proxy.__serialize__({ 'topics' => [target] }.with_indifferent_access)

      expect(configured).to eq false
    end

  end

end
