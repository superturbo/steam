require 'spec_helper'

require_relative '../../../support/content_entry_repository_context'

describe Locomotive::Steam::Models::AssociationPreloader do

  include_context 'content entry repository'

  let(:repository) { Locomotive::Steam::ContentEntryRepository.new(adapter, site, locale, content_type_repository) }

  let(:field) { instance_double('Field', name: :author, type: :belongs_to, association_options: { target_id: 2 }) }
  let(:type)  { build_content_type('Articles', label_field_name: :title, association_fields: [field], fields_with_default: []) }
  let(:entries) do
    [
      { content_type_id: 1, _id: 'a1', title: 'One',   author_id: 'john-doe' },
      { content_type_id: 1, _id: 'a2', title: 'Two',   author_id: 'jane-doe' },
      { content_type_id: 1, _id: 'a3', title: 'Three', author_id: 'john-doe' },
      { content_type_id: 1, _id: 'a4', title: 'Four',  author_id: nil },
      { content_type_id: 1, _id: 'a5', title: 'Five' }
    ]
  end

  let(:other_type) do
    build_content_type('Authors', _id: 2, label_field_name: :name, fields: _fields,
                       fields_by_name: { name: instance_double('Field', name: :name, type: :string) },
                       fields_with_default: [])
  end
  let(:other_entries) do
    [
      { content_type_id: 2, _id: 'john-doe', name: 'John Doe' },
      { content_type_id: 2, _id: 'jane-doe', name: 'Jane Doe' }
    ]
  end

  let(:type_repository) { instance_double('ArticleFields', selects: [], belongs_to: [], many_to_many: [], dates_and_date_times: [], numbers: [], booleans: []) }

  before do
    allow(type).to receive(:fields).and_return(type_repository)
    allow(content_type_repository).to receive(:find).and_return(other_type)
  end

  # The window loads from the parent collection; targets come from the
  # counted one.
  def preloaded_window
    repository.with(type).all.tap do |window|
      described_class.attach(window)

      @target_queries = 0
      allow(adapter).to receive(:collection) { @target_queries += 1; loaded(other_entries) }
    end
  end

  attr_reader :target_queries

  it 'reads nothing until an association is read' do
    preloaded_window

    expect(target_queries).to eq 0
    expect(content_type_repository).not_to have_received(:find)
  end

  it 'reads the first unique target with one query' do
    window = preloaded_window

    expect(window[0].author.name).to eq 'John Doe'
    expect(target_queries).to eq 1
  end

  it 'uses one direct and one batch query for the whole window' do
    window = preloaded_window

    expect(window.map { |entry| entry.author&.name })
      .to eq ['John Doe', 'Jane Doe', 'John Doe', nil, nil]
    expect(target_queries).to eq 2
  end

  it 'configures the target content type once for the window' do
    preloaded_window.each { |entry| entry.author&.name }

    expect(content_type_repository).to have_received(:find).with(2).once
  end

  it 'gives each owner its own target object' do
    window = preloaded_window

    window[0].author[:name] = 'Changed'

    expect(window[2].author.name).to eq 'John Doe'
    expect(window[0].author).not_to equal window[2].author
  end

  it 'resolves null and missing links without any query' do
    window = preloaded_window

    expect(window[3].author&.name).to eq nil
    expect(window[4].author&.name).to eq nil
    expect(target_queries).to eq 0
    expect(content_type_repository).not_to have_received(:find)
  end

  it 'a copied entry reads on its own, outside the window cache' do
    window = preloaded_window
    copy   = window[1].dup

    expect(copy.author.name).to eq 'Jane Doe'
    expect(window[1].author.name).to eq 'Jane Doe'
    expect(target_queries).to eq 2
  end

  context 'links spelled differently from the stored identities' do

    let(:entries) do
      [
        { content_type_id: 1, _id: 'a1', title: 'One',   author_id: 'JOHN-DOE' },
        { content_type_id: 1, _id: 'a2', title: 'Two',   author_id: 'JANE-DOE' },
        { content_type_id: 1, _id: 'a3', title: 'Three', author_id: 'JACK-DOE' }
      ]
    end
    let(:other_entries) do
      [
        { content_type_id: 2, _id: 'john-doe', name: 'John Doe' },
        { content_type_id: 2, _id: 'jane-doe', name: 'Jane Doe' },
        { content_type_id: 2, _id: 'jack-doe', name: 'Jack Doe' }
      ]
    end

    before { allow(adapter).to receive(:make_id) { |id| id.to_s.downcase } }

    it 'finds and batches under the adapter identity, exactly like find' do
      window = preloaded_window

      expect(window.map { |entry| entry.author.name })
        .to eq ['John Doe', 'Jane Doe', 'Jack Doe']
      expect(target_queries).to eq 2
    end

  end

  context 'a link no target answers' do

    let(:entries) do
      [
        { content_type_id: 1, _id: 'a1', title: 'One', author_id: 'ghost' },
        { content_type_id: 1, _id: 'a2', title: 'Two', author_id: 'ghost' }
      ]
    end

    it 'asks once and remembers the absence' do
      window = preloaded_window

      expect(window[0].author&.name).to eq nil
      expect(window[1].author&.name).to eq nil
      expect(target_queries).to eq 1
    end

  end

  context 'a target with a composite [mongo_id, slug] identity (synced entries)' do

    let(:entries) do
      [
        { content_type_id: 1, _id: 'a1', title: 'One', author_id: 'john-doe' },
        { content_type_id: 1, _id: 'a2', title: 'Two', author_id: '5baf7d38a953300567956448' }
      ]
    end
    let(:other_entries) { [{ content_type_id: 2, _id: ['5baf7d38a953300567956448', 'john-doe'], name: 'John Doe' }] }

    it 'serves either identity component from one load' do
      window = preloaded_window

      expect(window[0].author.name).to eq 'John Doe'
      expect(window[1].author.name).to eq 'John Doe'
      expect(target_queries).to eq 1
    end

  end

  context 'a hidden target' do

    let(:other_entries) do
      [
        { content_type_id: 2, _id: 'john-doe', name: 'John Doe' },
        { content_type_id: 2, _id: 'jane-doe', name: 'Jane Doe', _visible: false }
      ]
    end

    it 'stays hidden through the find' do
      window = preloaded_window

      expect(window[1].author&.name).to eq nil
    end

    it 'stays hidden through the batch' do
      window = preloaded_window

      expect(window[0].author.name).to eq 'John Doe'
      expect(window[1].author&.name).to eq nil
    end

  end

  context 'two belongs_to fields' do

    let(:maker_field) { instance_double('Field', name: :maker, type: :belongs_to, association_options: { target_id: 3 }) }
    let(:type)        { build_content_type('Articles', label_field_name: :title, association_fields: [field, maker_field], fields_with_default: []) }
    let(:entries) do
      [
        { content_type_id: 1, _id: 'a1', title: 'One', author_id: 'john-doe', maker_id: 'acme' },
        { content_type_id: 1, _id: 'a2', title: 'Two', author_id: 'jane-doe', maker_id: 'globex' }
      ]
    end
    let(:maker_type) do
      build_content_type('Makers', _id: 3, label_field_name: :name, fields: _fields,
                         fields_by_name: { name: instance_double('Field', name: :name, type: :string) },
                         fields_with_default: [])
    end
    let(:other_entries) do
      [
        { content_type_id: 2, _id: 'john-doe', name: 'John Doe' },
        { content_type_id: 2, _id: 'jane-doe', name: 'Jane Doe' },
        { content_type_id: 3, _id: 'acme',     name: 'ACME' },
        { content_type_id: 3, _id: 'globex',   name: 'Globex' }
      ]
    end

    before do
      allow(content_type_repository).to receive(:find).with(2).and_return(other_type)
      allow(content_type_repository).to receive(:find).with(3).and_return(maker_type)
    end

    it 'batches each association independently' do
      window = preloaded_window

      expect(window.map { |entry| entry.author.name }).to eq ['John Doe', 'Jane Doe']
      expect(window.map { |entry| entry.maker.name }).to eq ['ACME', 'Globex']
      expect(target_queries).to eq 4
      expect(content_type_repository).to have_received(:find).with(2).once
      expect(content_type_repository).to have_received(:find).with(3).once
    end

  end

  context 'a window larger than one batch' do

    let(:entries) do
      linked = 1.upto(150).map { |i| { content_type_id: 1, _id: "a#{i}", title: "T#{i}", author_id: "author-#{i}" } }

      # A duplicate inside the first batch pins the operand dedup.
      linked.insert(2, { content_type_id: 1, _id: 'b1', title: 'Dup', author_id: 'author-5' })
      linked << { content_type_id: 1, _id: 'b2', title: 'None', author_id: nil }
    end
    let(:other_entries) do
      1.upto(150).map { |i| { content_type_id: 2, _id: "author-#{i}", name: "Author #{i}" } }
    end

    # After the direct read, the first batch spans the next hundred ids, so
    # author-102 sits right behind the boundary.
    it 'loads only the batch holding the miss, never the untouched ones' do
      window = preloaded_window

      window[0].author.name
      window[1].author.name
      window[50].author.name
      expect(target_queries).to eq 2

      window[102].author.name
      expect(target_queries).to eq 3
    end

    it 'sends compact unique batches of no more than a hundred ids' do
      window  = preloaded_window
      batches = []

      target_repository = window.first.associations.fetch(:author).__configured_repository__

      allow(target_repository).to receive(:all).and_wrap_original do |original, *args, &block|
        batches << (args.first || {})['_id.in']
        original.call(*args, &block)
      end

      window.each { |entry| entry.author&.name }

      expect(batches.map(&:size)).to eq [100, 49]
      expect(batches.flatten).to eq batches.flatten.compact.uniq
    end

  end

end
