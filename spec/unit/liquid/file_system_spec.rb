require 'spec_helper'

describe Locomotive::Steam::Liquid::FileSystem do

  let(:section_finder) { instance_double('SectionFinder') }
  let(:snippet_finder) { instance_double('SnippetFinder') }
  let(:instance) { described_class.new(section_finder: section_finder, snippet_finder: snippet_finder) }

  describe '#read_template_file' do

    let(:template_path) { nil }

    subject { instance.read_template_file(template_path) }

    context 'unknown type' do

      let(:template_path) { 'unknown--template' }

      it { expect { subject }.to raise_error('Liquid error: This liquid context does not allow unknown.') }

    end

    context 'a bare name defaults to a snippet (how Liquid 5 include passes them)' do

      let(:template_path) { 'footer' }
      let(:snippet)       { instance_double('Snippet', liquid_source: 'built by NoCoffee') }

      before { allow(snippet_finder).to receive(:find).with('footer').and_return(snippet) }

      it { is_expected.to eq 'built by NoCoffee' }

      context 'missing snippet' do

        let(:snippet) { nil }

        it { expect { subject }.to raise_error('Liquid error: Unable to find footer in the snippets folder') }

      end

    end

  end

end
