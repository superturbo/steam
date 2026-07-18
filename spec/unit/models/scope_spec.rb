require 'spec_helper'

describe Locomotive::Steam::Models::Scope do

  let(:site)    { instance_double('Site', _id: 1) }
  let(:locale)  { :en }
  let(:context) { nil }
  let(:scope)   { described_class.new(site, locale, context) }

  describe '#to_key' do

    subject { scope.to_key }

    it { is_expected.to eq 'site_1' }

    context 'with a content type for instance' do

      let(:content_type) { instance_double('ContentType', _id: 42) }
      let(:context) { { content_type: content_type } }

      it { is_expected.to eq 'site_1_content_type_42' }

    end

  end

  describe '#dup' do

    let(:content_type) { instance_double('ContentType', _id: 42) }
    let(:context)      { { content_type: content_type } }
    subject(:copy)     { scope.dup }

    it 'shares the site (same tenant)' do
      expect(copy.site).to be(scope.site)
    end

    it 'isolates the context so the copy cannot mutate the original' do
      copy.context[:content_type] = instance_double('ContentType', _id: 7)
      expect(scope.context[:content_type]).to be(content_type)
    end

  end

end
