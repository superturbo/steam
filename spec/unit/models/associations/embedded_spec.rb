require 'spec_helper'

describe Locomotive::Steam::Models::EmbeddedAssociation do

  let(:repository_klass) do
    Class.new do
      def initialize(_adapter); end
      attr_accessor :scope, :page
    end
  end

  let(:scope)       { Locomotive::Steam::Models::Scope.new(nil, :en) }
  let(:association) { described_class.new(repository_klass, [], scope, mapper_name: 'pages') }
  let(:entity)      { Object.new }
  let(:other)       { Object.new }

  before { association.__attach__(entity) }

  describe '#dup' do

    subject { association.dup }

    it 'answers for the entity it is attached to' do
      subject.__attach__(other)

      expect(association.page).to be(entity)
      expect(subject.page).to be(other)
    end

    it 'reads the locale the parent repository is left holding' do
      copy = subject
      scope.locale = :fr

      expect(copy.scope.locale).to eq :fr
    end

  end

end
