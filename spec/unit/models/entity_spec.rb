require 'spec_helper'

describe Locomotive::Steam::Models::Entity do

  let(:klass) { Class.new { include Locomotive::Steam::Models::Entity } }
  let(:title) { Locomotive::Steam::Models::I18nField.new(:title, 'en' => 'Hello') }
  let(:entity) { klass.new(name: 'Ada', title: title) }

  describe '#dup' do

    subject { entity.dup }

    it 'changes a plain attribute on its own' do
      subject[:name] = 'Grace'

      expect(entity.name).to eq 'Ada'
    end

    it 'changes a locale of a localized attribute on its own' do
      subject.title[:en] = 'Bonjour'

      expect(entity.title[:en]).to eq 'Hello'
    end

  end

end
