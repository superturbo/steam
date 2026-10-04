require 'spec_helper'

describe Locomotive::Steam::Liquid::Drops::SectionEditorSettingData do

  let(:section)      { instance_double('Section', definition: { 'settings' => [{ 'id' => 'title', 'type' => 'text' }], 'blocks' => [] }) }
  let(:section_drop) { Locomotive::Steam::Liquid::Drops::Section.new(section, { 'id' => %(a" onclick="b) }) }
  let(:drop)         { described_class.new(section).tap { |drop| drop.context = ::Liquid::Context.new('section' => section_drop) } }

  it 'encodes the id of the section in the setting attribute' do
    expect(drop.liquid_method_missing('title')).to eq %( data-locomotive-editor-setting="section-a&quot; onclick=&quot;b.title")
  end

  context 'for a setting the editor renders' do

    let(:drop) { described_class.new(section, attribute: 'data-locomotive-editor-setting-render').tap { |drop| drop.context = ::Liquid::Context.new('section' => section_drop) } }

    it 'encodes the id of the section in the render attribute' do
      expect(drop.liquid_method_missing('title')).to eq %( data-locomotive-editor-setting-render="section-a&quot; onclick=&quot;b.title")
    end

  end

end
