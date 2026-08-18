require 'spec_helper'

require_relative '../../../support/content_entry_repository_context'

describe Locomotive::Steam::Models::AssociationPreloader do

  include_context 'content entry repository'

  let(:repository) { Locomotive::Steam::ContentEntryRepository.new(adapter, site, locale, content_type_repository) }

  let(:field) do
    instance_double('Field', name: :articles, type: :has_many,
                             association_options: { target_id: 2, inverse_of: :author, order_by: 'position_in_author' })
  end
  let(:type) do
    build_content_type('Authors', label_field_name: :name, association_fields: [field],
                       fields_by_name: { articles: field }, fields_with_default: [])
  end
  let(:entries) do
    [
      { content_type_id: 1, _id: 'u1', name: 'U1' },
      { content_type_id: 1, _id: 'u2', name: 'U2' },
      { content_type_id: 1, _id: 'u3', name: 'U3' },
      { content_type_id: 1, _id: 'u4', name: 'U4' }
    ]
  end

  let(:title_field)   { instance_double('Field', name: :title, type: :string) }
  let(:author_field)  { instance_double('Field', name: :author, type: :belongs_to) }
  let(:target_fields) { instance_double('Fields', selects: [], belongs_to: [author_field], many_to_many: [], dates_and_date_times: [], numbers: [], booleans: []) }
  let(:other_type) do
    build_content_type('Articles', _id: 2, label_field_name: :title, fields: target_fields,
                       fields_by_name: { title: title_field, author: author_field },
                       fields_with_default: [])
  end
  let(:other_entries) do
    [
      { content_type_id: 2, _id: 'x1', title: 'X1', author_id: 'u1', position_in_author: 1 },
      { content_type_id: 2, _id: 'x2', title: 'X2', author_id: 'u1', position_in_author: 0 },
      { content_type_id: 2, _id: 'y1', title: 'Y1', author_id: 'u2', position_in_author: 0 },
      { content_type_id: 2, _id: 'z1', title: 'Z1', author_id: 'u3', position_in_author: 0 }
    ]
  end

  let(:author_fields) { instance_double('AuthorFields', selects: [], belongs_to: [], many_to_many: [], dates_and_date_times: [], numbers: [], booleans: []) }

  before do
    allow(type).to receive(:fields).and_return(author_fields)
    allow(content_type_repository).to receive(:find).and_return(other_type)
  end

  # Count child reads after materializing the owner window.
  def preloaded_window
    repository.with(type).all.tap do |window|
      described_class.attach(window)

      @child_queries = 0
      allow(adapter).to receive(:collection) { @child_queries += 1; loaded(other_entries) }
    end
  end

  attr_reader :child_queries

  it 'reads nothing until an association is read' do
    preloaded_window

    expect(child_queries).to eq 0
    expect(content_type_repository).not_to have_received(:find)
  end

  it 'reads the first owner directly and batches the rest' do
    window = preloaded_window

    expect(window[0].articles.all.map(&:title)).to eq %w(X2 X1)
    expect(child_queries).to eq 1

    expect(window[1].articles.all.map(&:title)).to eq %w(Y1)
    expect(window[2].articles.all.map(&:title)).to eq %w(Z1)
    expect(window[3].articles.all.map(&:title)).to eq []

    expect(child_queries).to eq 3
    expect(content_type_repository).to have_received(:find).with(2).once
  end

  it 'caches the empty answer of a childless owner' do
    window = preloaded_window

    window[0].articles.all
    window[1].articles.all
    window[3].articles.all
    window[3].articles.all

    expect(child_queries).to eq 3
  end

  context 'a batched group with interleaved positions' do

    let(:other_entries) do
      [
        { content_type_id: 2, _id: 'x1', title: 'X1', author_id: 'u1', position_in_author: 0 },
        { content_type_id: 2, _id: 'y1', title: 'Y1', author_id: 'u2', position_in_author: 1 },
        { content_type_id: 2, _id: 'y2', title: 'Y2', author_id: 'u2', position_in_author: 0 },
        { content_type_id: 2, _id: 'z1', title: 'Z1', author_id: 'u3', position_in_author: 0 }
      ]
    end

    it 'keeps the group in its position order' do
      window = preloaded_window

      window[0].articles.all

      expect(window[1].articles.all.map(&:title)).to eq %w(Y2 Y1)
      expect(window[0].articles.all.map(&:title)).to eq %w(X1)
    end

  end

  it 'gives each owner its own child objects' do
    window = preloaded_window

    window[0].articles.all
    first = window[1].articles.all.first
    first[:title] = 'Changed'

    expect(window[1].articles.all.map(&:title)).to eq %w(Y1)
  end

  context 'a window of two owners' do

    let(:entries) do
      [
        { content_type_id: 1, _id: 'u1', name: 'U1' },
        { content_type_id: 1, _id: 'u2', name: 'U2' }
      ]
    end

    it 'keeps both reads per-parent rather than probing' do
      window = preloaded_window

      expect(window[0].articles.all.map(&:title)).to eq %w(X2 X1)
      expect(window[1].articles.all.map(&:title)).to eq %w(Y1)

      expect(child_queries).to eq 2
    end

  end

  context 'children beyond the batch budget' do

    let(:other_entries) do
      big = 1.upto(120).map do |i|
        { content_type_id: 2, _id: "b#{i}", title: "B#{i}", author_id: 'u2', position_in_author: i }
      end
      big + [
        { content_type_id: 2, _id: 'x1', title: 'X1', author_id: 'u1', position_in_author: 0 },
        { content_type_id: 2, _id: 'z1', title: 'Z1', author_id: 'u3', position_in_author: 0 },
        { content_type_id: 2, _id: 'w1', title: 'W1', author_id: 'u4', position_in_author: 0 }
      ]
    end

    it 'falls back to per-parent reads and keeps serving what fits' do
      window = preloaded_window

      expect(window[0].articles.all.map(&:title)).to eq %w(X1)
      expect(window[1].articles.all.length).to eq 120
      expect(window[2].articles.all.map(&:title)).to eq %w(Z1)

      expect(child_queries).to eq 4
    end

    it 'keeps an oversized first owner out of the shared probe' do
      window = preloaded_window

      expect(window[1].articles.all.length).to eq 120
      expect(window[0].articles.all.map(&:title)).to eq %w(X1)
      expect(window[2].articles.all.map(&:title)).to eq %w(Z1)
      expect(window[3].articles.all.map(&:title)).to eq %w(W1)

      expect(child_queries).to eq 3
    end

    it 'never probes an oversized owner again' do
      window = preloaded_window

      window[0].articles.all
      window[1].articles.all
      window[1].articles.all

      expect(child_queries).to eq 4
    end

  end

  context 'a batch outgrown between the probe and the find' do

    let(:other_entries) do
      filler = 1.upto(96).map do |i|
        { content_type_id: 2, _id: "f#{i}", title: "F#{i}", author_id: 'u1', position_in_author: i }
      end
      filler + [
        { content_type_id: 2, _id: 'y1', title: 'Y1', author_id: 'u2', position_in_author: 0 },
        { content_type_id: 2, _id: 'y2', title: 'Y2', author_id: 'u2', position_in_author: 1 },
        { content_type_id: 2, _id: 'y3', title: 'Y3', author_id: 'u2', position_in_author: 2 },
        { content_type_id: 2, _id: 'z1', title: 'Z1', author_id: 'u3', position_in_author: 0 },
        { content_type_id: 2, _id: 'z2', title: 'Z2', author_id: 'u3', position_in_author: 1 }
      ]
    end

    it 'discards the batch instead of breaking the budget' do
      window = preloaded_window

      window[0].articles.all
      allow(adapter).to receive(:count_up_to).and_return(3)

      expect(window[1].articles.all.map(&:title)).to eq %w(Y1 Y2 Y3)
      expect(child_queries).to eq 3
    end

  end

  context 'a hidden child inside a batched group' do

    let(:other_entries) do
      [
        { content_type_id: 2, _id: 'x1', title: 'X1', author_id: 'u1', position_in_author: 0 },
        { content_type_id: 2, _id: 'y1', title: 'Y1', author_id: 'u2', position_in_author: 0, _visible: false },
        { content_type_id: 2, _id: 'y2', title: 'Y2', author_id: 'u2', position_in_author: 1 },
        { content_type_id: 2, _id: 'z1', title: 'Z1', author_id: 'u3', position_in_author: 0 }
      ]
    end

    it 'stays hidden through both the probe and the find' do
      window = preloaded_window

      window[0].articles.all

      expect(window[1].articles.all.map(&:title)).to eq %w(Y2)
    end

  end

  context 'pending children exactly at the budget' do

    let(:entries) do
      [{ content_type_id: 1, _id: 'u1', name: 'U1' }] +
        2.upto(5).map { |i| { content_type_id: 1, _id: "u#{i}", name: "U#{i}" } }
    end
    let(:other_entries) do
      1.upto(100).map do |i|
        { content_type_id: 2, _id: "b#{i}", title: "B#{i}", author_id: "u#{2 + (i % 4)}", position_in_author: i }
      end
    end

    it 'still batches a full budget' do
      window = preloaded_window

      window[0].articles.all
      window[1].articles.all

      expect(window[2].articles.all.length).to eq 25
      expect(child_queries).to eq 3
    end

  end

  context 'pending children one past the budget' do

    let(:entries) do
      [{ content_type_id: 1, _id: 'u1', name: 'U1' }] +
        2.upto(5).map { |i| { content_type_id: 1, _id: "u#{i}", name: "U#{i}" } }
    end
    let(:other_entries) do
      1.upto(101).map do |i|
        { content_type_id: 2, _id: "b#{i}", title: "B#{i}", author_id: "u#{2 + (i % 4)}", position_in_author: i }
      end
    end

    it 'probes once and leaves every read per-parent' do
      window = preloaded_window

      window.each { |owner| owner.articles.all }

      expect(child_queries).to eq 6
    end

  end

  context 'an owner right past the operand budget' do

    let(:entries) do
      1.upto(120).map do |i|
        _id = i == 2 ? ['aaaabbbbccccddddeeee0002', 'u2'] : "u#{i}"
        { content_type_id: 1, _id: _id, name: "U#{i}" }
      end
    end
    let(:other_entries) do
      [
        { content_type_id: 2, _id: 'c2',   title: 'C2',   author_id: 'u2',   position_in_author: 0 },
        { content_type_id: 2, _id: 'c101', title: 'C101', author_id: 'u101', position_in_author: 0 }
      ]
    end

    # u2's two identity components leave room for u3..u100 alone.
    it 'leaves the hundred-and-first operand to the next batch' do
      window = preloaded_window

      expect(window[0].articles.all).to eq []
      expect(window[1].articles.all.map(&:title)).to eq %w(C2)
      expect(child_queries).to eq 3

      expect(window[100].articles.all.map(&:title)).to eq %w(C101)
      expect(child_queries).to eq 5
    end

  end

  context 'a far owner read first' do

    let(:entries) do
      1.upto(120).map { |i| { content_type_id: 1, _id: "u#{i}", name: "U#{i}" } }
    end
    let(:other_entries) do
      109.upto(112).map do |i|
        { content_type_id: 2, _id: "c#{i}", title: "C#{i}", author_id: "u#{i}", position_in_author: 0 }
      end
    end

    it 'batches forward from the owner that pays for the probe' do
      window = preloaded_window

      expect(window[109].articles.all.map(&:title)).to eq %w(C110)
      expect(window[110].articles.all.map(&:title)).to eq %w(C111)
      expect(window[111].articles.all.map(&:title)).to eq %w(C112)
      expect(child_queries).to eq 3

      window[0].articles.all

      expect(child_queries).to eq 5
    end

  end

  context 'textual identity components under a MongoDB-like adapter' do

    let(:entries) do
      [
        { content_type_id: 1, _id: ['aaaabbbbccccddddeeee0001', 'john-doe'], name: 'U1' },
        { content_type_id: 1, _id: ['aaaabbbbccccddddeeee0002', 'jane-doe'], name: 'U2' },
        { content_type_id: 1, _id: 'u3', name: 'U3' },
        { content_type_id: 1, _id: 'u4', name: 'U4' }
      ]
    end
    let(:other_entries) do
      [
        { content_type_id: 2, _id: 'c1', title: 'C1', author_id: 'john-doe', position_in_author: 0 },
        { content_type_id: 2, _id: 'c2', title: 'C2', author_id: 'jane-doe', position_in_author: 0 }
      ]
    end

    before do
      allow(adapter).to receive(:make_id) { |id| id.to_s.match?(/\A[0-9a-f]{24}\z/) ? id : false }
    end

    it 'never groups two different texts the adapter cannot make ids of' do
      window = preloaded_window

      window[0].articles.all

      expect(window[1].articles.all.map(&:title)).to eq %w(C2)
      expect(window[2].articles.all).to eq []
    end

  end

  context 'owners sharing an identity component' do

    let(:entries) do
      [
        { content_type_id: 1, _id: 'u1', name: 'U1' },
        { content_type_id: 1, _id: ['aaaabbbbccccddddeeee0002', 'aaaabbbbccccddddeeee9999'], name: 'U2' },
        { content_type_id: 1, _id: ['aaaabbbbccccddddeeee9999', 'u3'], name: 'U3' },
        { content_type_id: 1, _id: 'u4', name: 'U4' }
      ]
    end
    let(:other_entries) do
      [
        { content_type_id: 2, _id: 'x1', title: 'X1', author_id: 'u1', position_in_author: 0 },
        { content_type_id: 2, _id: 'y1', title: 'Y1', author_id: 'aaaabbbbccccddddeeee0002', position_in_author: 0 },
        { content_type_id: 2, _id: 's1', title: 'S1', author_id: 'aaaabbbbccccddddeeee9999', position_in_author: 1 },
        { content_type_id: 2, _id: 'z1', title: 'Z1', author_id: 'u3', position_in_author: 0 }
      ]
    end

    it 'hands the shared child to every owner it answers, like per-parent reads' do
      window = preloaded_window

      window[0].articles.all

      expect(window[1].articles.all.map(&:title)).to eq %w(Y1 S1)
      expect(window[2].articles.all.map(&:title)).to eq %w(Z1 S1)
    end

  end

  context 'owners with composite identities' do

    let(:entries) do
      [
        { content_type_id: 1, _id: 'u1', name: 'U1' },
        { content_type_id: 1, _id: ['aaaabbbbccccddddeeee0002', 'u2'], name: 'U2' },
        { content_type_id: 1, _id: 'u3', name: 'U3' },
        { content_type_id: 1, _id: 'u4', name: 'U4' }
      ]
    end
    let(:other_entries) do
      [
        { content_type_id: 2, _id: 'x1', title: 'X1', author_id: 'u1', position_in_author: 0 },
        { content_type_id: 2, _id: 'y1', title: 'Y1', author_id: 'aaaabbbbccccddddeeee0002', position_in_author: 0 },
        { content_type_id: 2, _id: 'y2', title: 'Y2', author_id: 'u2', position_in_author: 1 },
        { content_type_id: 2, _id: 'z1', title: 'Z1', author_id: 'u3', position_in_author: 0 }
      ]
    end

    it 'gathers the children of every identity component' do
      window = preloaded_window

      window[0].articles.all

      expect(window[1].articles.all.map(&:title)).to eq %w(Y1 Y2)
    end

  end

  it 'keeps a runtime-scoped read on the per-parent path, outside the cache' do
    window = preloaded_window

    window[0].articles.all
    window[1].articles.all
    expect(child_queries).to eq 3

    scoped = repository.value_for(window[1], :articles, order_by: 'title.desc')

    expect(scoped.all.map(&:title)).to eq %w(Y1)
    expect(child_queries).to eq 4

    expect(window[1].articles.all.map(&:title)).to eq %w(Y1)
    expect(child_queries).to eq 4
  end

  it 'keeps an inner window on the per-parent path' do
    window = preloaded_window

    expect(window[0].articles.load_window(nil, 0, 1).map(&:title)).to eq %w(X2)
    expect(window[0].articles.load_window(nil, 0, 1).map(&:title)).to eq %w(X2)

    expect(child_queries).to eq 2
  end

  it 'hands Liquid a collection served by the preloader' do
    window = preloaded_window

    window[0].articles.all
    drop = window[1].articles.to_liquid
    drop.context = ::Liquid::Context.new({}, {}, {})

    expect(drop.load_slice(0, nil).map(&:title)).to eq %w(Y1)
    expect(child_queries).to eq 3
  end

end
