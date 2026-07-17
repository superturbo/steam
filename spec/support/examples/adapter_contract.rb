# Public adapter surface used by Models::Repository.
shared_examples_for 'a repository adapter' do

  %i(query find count create update inc delete key make_id base_url).each do |method|
    it("responds to ##{method}") { expect(adapter).to respond_to(method) }
  end

end
