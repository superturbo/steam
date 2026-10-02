# Specs run in test mode, where Steam logs values as given.
RSpec.shared_context 'filtered logs' do
  before { allow(Locomotive::Steam.configuration).to receive(:mode).and_return(:production) }
end
