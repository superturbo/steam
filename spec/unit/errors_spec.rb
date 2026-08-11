require 'spec_helper'

describe Locomotive::Steam::TemplateError do

  let(:message)   { 'Wrong syntax' }
  let(:file)      { 'template.liquid.haml' }
  let(:source)    { %w(a b c d e f g h i j k l m n o p q r s t u v w y z).join("\n") }
  let(:line)      { 10 }
  let(:backtrace) { 'Backtrace' }
  let(:error)     { described_class.new(message, file, source, line, backtrace) }

  describe '#code_lines' do

    subject { error.code_lines }

    it { is_expected.to eq [[5, 'e'], [6, 'f'], [7, 'g'], [8, 'h'], [9, 'i'], [10, 'j'], [11, 'k'], [12, 'l'], [13, 'm'], [14, 'n'], [15, 'o']] }

  end

  describe '#backtrace' do

    subject { error.original_backtrace }

    it { is_expected.to eq 'Backtrace' }

  end

end

describe Locomotive::Steam::JsonParsingError do

  context 'when the parse error message carries a line number' do
    let(:error) { double('error', message: 'unexpected token at line 3, column 5', backtrace: ['a.rb:1']) }
    subject     { described_class.new(error, 'index', '{ bad }') }

    it('extracts the line number') { expect(subject.line_number).to eq(3) }
    it('prefixes the message')     { expect(subject.message).to start_with('JSON parsing error - ') }
  end

  context 'when the parse error message has no line number' do
    let(:error) { double('error', message: 'boom', backtrace: []) }
    subject     { described_class.new(error, 'index', '{ bad }') }

    it('defaults the line number to zero') { expect(subject.line_number).to eq(0) }
  end

end

describe Locomotive::Steam::UnsupportedSchemaError do

  it 'carries a stable reason' do
    error = described_class.new(:unsupported_localization,
                                'posts.yml, field author: a belongs_to field cannot be localized')

    expect(error.reason).to eq :unsupported_localization
  end

  it 'refuses a reason it does not know' do
    expect { described_class.new(:made_up, 'x') }.to raise_error(ArgumentError)
  end

end

describe Locomotive::Steam::RenderError do

  let(:error) { double('error', message: 'boom', line_number: 2, backtrace: []) }
  subject     { described_class.new(error, 'index', 'source') }

  it('prefixes the message') { expect(subject.message).to start_with('Render - ') }

end
