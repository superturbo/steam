require 'spec_helper'

describe Locomotive::Steam::Models::Concerns::Validation::Errors do

  subject(:errors) { described_class.new }

  around { |example| I18n.with_locale(:en) { example.run } }

  it 'keeps the code of each error beside its message' do
    errors.add(:email, :blank)
    errors.add(:email, :taken)
    errors.add(:password, :too_short, count: 6)

    expect(errors.codes).to eq('email' => [:blank, :taken], 'password' => [:too_short])
    expect(errors[:email].first).to eq "can't be blank"
  end

  it 'returns the messages of the attribute, as it did before codes' do
    expect(errors.add(:email, :blank)).to eq ["can't be blank"]
  end

  it 'keeps the invalid code for a message given as text, never the text' do
    errors.add(:title, 'quotes secret-42')

    expect(errors.codes).to eq('title' => [:invalid])
  end

  it 'changes neither the codes nor the messages when the message cannot be built' do
    expect { errors.add(:password_confirmation, :confirmation, count: 1) }.to raise_error(I18n::MissingInterpolationArgument)

    expect(errors).to be_empty
    expect(errors.codes).to be_empty
  end

  it 'clears the codes with the messages' do
    errors.add(:email, :blank)

    expect(errors.clear).to be(errors.messages)

    expect(errors).to be_empty
    expect(errors.codes).to be_empty
  end

end
