require 'spec_helper'

describe Locomotive::Steam::SiteFinderService do

  let(:repository) { instance_double('SiteRepository') }

  it 'finds the site of the request host' do
    site = double('Site')
    allow(repository).to receive(:by_domain).with('acme.example').and_return(site)

    expect(described_class.new(repository, instance_double('Request', host: 'acme.example')).find).to eq site
  end

  it 'finds no site without a request' do
    expect(repository).not_to receive(:by_domain)

    expect(described_class.new(repository, nil).find).to be_nil
  end

end
