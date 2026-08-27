require 'spec_helper'

describe Locomotive::Steam::LiquidCriteria do

  it 'owns a copy of the attributes it wrapped' do
    attributes = { 'title' => 'Before' }
    criteria   = described_class.wrap(attributes)

    attributes['title'] = 'After'

    expect(criteria.attributes).to eq('title' => 'Before')
  end

end
