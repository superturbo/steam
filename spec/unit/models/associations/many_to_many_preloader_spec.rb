require 'spec_helper'

require_relative '../../../support/content_entry_repository_context'

describe Locomotive::Steam::Models::AssociationPreloader do

  include_context 'content entry repository'

  let(:repository) { Locomotive::Steam::ContentEntryRepository.new(adapter, site, locale, content_type_repository) }

  before { allow(content_type_repository).to receive(:find).and_return(other_type) }

  # Count target reads after materializing the owner window.
  def preloaded_window
    repository.with(type).all.tap do |window|
      described_class.attach(window)

      @target_queries = 0
      allow(adapter).to receive(:collection) { @target_queries += 1; loaded(other_entries) }
    end
  end

  attr_reader :target_queries

  describe 'a many_to_many association' do

    let(:field) { instance_double('Field', name: :articles, type: :many_to_many, association_options: { target_id: 2, inverse_of: :authors }) }
    let(:type)  { build_content_type('Authors', label_field_name: :name, association_fields: [field], fields_by_name: { articles: field }, fields_with_default: []) }
    let(:entries) do
      [
        { content_type_id: 1, _id: 'u1', name: 'One',   article_ids: ['b', 'a'] },
        { content_type_id: 1, _id: 'u2', name: 'Two',   article_ids: ['a', 'c'] },
        { content_type_id: 1, _id: 'u3', name: 'Three', article_ids: ['d'] },
        { content_type_id: 1, _id: 'u4', name: 'Four',  article_ids: [] }
      ]
    end
    let(:other_type) do
      build_content_type('Articles', _id: 2, label_field_name: :title, fields: _fields,
                         fields_by_name: { title: instance_double('Field', name: :title, type: :string) },
                         fields_with_default: [])
    end
    let(:other_entries) do
      [
        { content_type_id: 2, _id: 'a', title: 'A' },
        { content_type_id: 2, _id: 'b', title: 'B' },
        { content_type_id: 2, _id: 'c', title: 'C' },
        { content_type_id: 2, _id: 'd', title: 'D' }
      ]
    end

    it 'reads nothing until the association is read' do
      preloaded_window

      expect(target_queries).to eq 0
    end

    it 'serves the whole window in the owner sequences with two target queries' do
      window = preloaded_window

      expect(window.map { |author| author.articles.all.map(&:title) })
        .to eq [%w(B A), %w(A C), %w(D), []]
      expect(target_queries).to eq 2
      expect(content_type_repository).to have_received(:find).with(2).once
    end

    it 'serves a repeated read from the cache without new queries' do
      window = preloaded_window

      window[0].articles.all
      window[0].articles.all

      expect(target_queries).to eq 1
    end

    it 'gives each owner its own target objects' do
      window = preloaded_window

      one = window[0].articles.all.detect { |article| article.title == 'A' }
      one[:title] = 'Changed'

      expect(window[1].articles.all.map(&:title)).to include 'A'
    end

    it 'does not query targets for an empty window' do
      window = preloaded_window

      expect(window[0].articles.load_window(nil, 0, 0)).to eq []
      expect(target_queries).to eq 0
    end

    it 'loads only the requested association window' do
      window = preloaded_window

      expect(window[0].articles.load_window(nil, 0, 1).map(&:title)).to eq %w(B)
      expect(target_queries).to eq 1

      expect(window[1].articles.load_window(nil, 0, 1).map(&:title)).to eq %w(A)
      expect(target_queries).to eq 2
    end

    it 'hands Liquid a collection served by the preloader' do
      window = preloaded_window

      drop = window[0].articles.to_liquid
      drop.context = ::Liquid::Context.new({}, {}, {})

      expect(drop.load_slice(0, 1).map(&:title)).to eq %w(B)
      expect(target_queries).to eq 1
    end

    it 'keeps the unrequested tail out of the cache' do
      window = preloaded_window

      window.each { |author| author.articles.load_window(nil, 0, 1) }
      expect(target_queries).to eq 2

      window[1].articles.all
      expect(target_queries).to eq 3
    end

    it 'keeps the target type scope next to the owner bound' do
      window = preloaded_window

      repository = window[0].articles.__load__.__getobj__

      expect(repository.local_conditions[:content_type_id]).to eq 2
      expect(repository.local_conditions[repository.k(:_id, :in)]).to eq %w(b a)
    end

    context 'hidden targets standing before the window' do

      let(:entries) { [{ content_type_id: 1, _id: 'u1', name: 'One', article_ids: ['b', 'a', 'c'] }] }
      let(:other_entries) do
        [
          { content_type_id: 2, _id: 'a', title: 'A' },
          { content_type_id: 2, _id: 'b', title: 'B', _visible: false },
          { content_type_id: 2, _id: 'c', title: 'C' }
        ]
      end

      it 'counts the offset over visible targets alone' do
        window = preloaded_window

        expect(window[0].articles.load_window(nil, 1, 1).map(&:title)).to eq %w(C)
      end

    end

    context 'a lone owner led by a hidden target' do

      let(:entries) { [{ content_type_id: 1, _id: 'u1', name: 'One', article_ids: ['b', 'a'] }] }
      let(:other_entries) do
        [
          { content_type_id: 2, _id: 'a', title: 'A' },
          { content_type_id: 2, _id: 'b', title: 'B', _visible: false }
        ]
      end

      it 'still reads the visible one behind it' do
        window = preloaded_window

        expect(window[0].articles.load_window(nil, 0, 1).map(&:title)).to eq %w(A)
      end

    end

    context 'an owner naming both components of one target' do

      let(:entries) do
        [{ content_type_id: 1, _id: 'u1', name: 'One',
           article_ids: ['aaaabbbbccccddddeeee0001', 'comp1'] }]
      end
      let(:other_entries) do
        [{ content_type_id: 2, _id: ['aaaabbbbccccddddeeee0001', 'comp1'],
           _slug: 'comp1', title: 'C1' }]
      end

      it 'answers the target once, at its first position' do
        window = preloaded_window

        expect(window[0].articles.all.map(&:title)).to eq %w(C1)
      end

    end

    context 'composite targets filling the alias space' do

      let(:entries) do
        [
          { content_type_id: 1, _id: 'u1', name: 'One', article_ids: 1.upto(60).map { |i| "comp#{i}" } },
          { content_type_id: 1, _id: 'u2', name: 'Two', article_ids: ['a'] }
        ]
      end
      let(:other_entries) do
        targets = 1.upto(60).map do |i|
          { content_type_id: 2, _id: ["aaaabbbbccccddddeeee#{format('%04d', i)}", "comp#{i}"],
            _slug: "comp#{i}", title: "C#{i}" }
        end
        targets << { content_type_id: 2, _id: 'a', title: 'A' }
      end

      it 'budgets the requested identities, not the alias keys' do
        window = preloaded_window

        expect(window[0].articles.all.length).to eq 60
        expect(window[1].articles.all.map(&:title)).to eq %w(A)
        window[1].articles.all

        expect(target_queries).to eq 2
      end

    end

    context 'every owner led by its own hidden target' do

      let(:entries) do
        1.upto(20).map { |i| { content_type_id: 1, _id: "u#{i}", name: "O#{i}", article_ids: ["h#{i}", "v#{i}"] } }
      end
      let(:other_entries) do
        hidden  = 1.upto(20).map { |i| { content_type_id: 2, _id: "h#{i}", title: "H#{i}", _visible: false } }
        visible = 1.upto(20).map { |i| { content_type_id: 2, _id: "v#{i}", title: "V#{i}" } }
        hidden + visible
      end

      it 'stays batched instead of growing per owner' do
        window = preloaded_window

        expect(window.map { |owner| owner.articles.load_window(nil, 0, 1).map(&:title) })
          .to eq 1.upto(20).map { |i| ["V#{i}"] }
        expect(target_queries).to eq 5
      end

    end

    context 'every owner led by one shared hidden target' do

      let(:entries) do
        1.upto(20).map { |i| { content_type_id: 1, _id: "u#{i}", name: "O#{i}", article_ids: ['h', "v#{i}"] } }
      end
      let(:other_entries) do
        visible = 1.upto(20).map { |i| { content_type_id: 2, _id: "v#{i}", title: "V#{i}" } }
        visible + [{ content_type_id: 2, _id: 'h', title: 'H', _visible: false }]
      end

      it 'answers the whole sweep with three queries' do
        window = preloaded_window

        expect(window.map { |owner| owner.articles.load_window(nil, 0, 1).map(&:title) })
          .to eq 1.upto(20).map { |i| ["V#{i}"] }
        expect(target_queries).to eq 3
      end

    end

    context 'owners holding only hidden targets' do

      let(:entries) do
        1.upto(3).map { |i| { content_type_id: 1, _id: "u#{i}", name: "O#{i}", article_ids: ["h#{i}"] } }
      end
      let(:other_entries) do
        1.upto(3).map { |i| { content_type_id: 2, _id: "h#{i}", title: "H#{i}", _visible: false } }
      end

      it 'answers every window empty without a continuation query' do
        window = preloaded_window

        expect(window.map { |owner| owner.articles.load_window(nil, 0, 1) }).to eq [[], [], []]
        expect(target_queries).to eq 2
      end

    end

    context 'a hidden head in front of an offset' do

      let(:entries) { [{ content_type_id: 1, _id: 'u1', name: 'One', article_ids: ['h1', 'v1', 'v2'] }] }
      let(:other_entries) do
        [{ content_type_id: 2, _id: 'h1', title: 'H1', _visible: false },
         { content_type_id: 2, _id: 'v1', title: 'V1' },
         { content_type_id: 2, _id: 'v2', title: 'V2' }]
      end

      it 'counts the offset over the visible targets behind it' do
        window = preloaded_window

        expect(window[0].articles.load_window(nil, 1, 1).map(&:title)).to eq %w(V2)
        expect(target_queries).to eq 2
      end

    end

    context 'a cached target behind the fallback boundary' do

      let(:entries) do
        [
          { content_type_id: 1, _id: 'u1', name: 'One',
            article_ids: ['a'] + 2.upto(100).map { |i| "c#{i}" } },
          { content_type_id: 1, _id: 'u2', name: 'Two', article_ids: ['x', 'a'] }
        ]
      end
      let(:other_entries) do
        targets = 2.upto(100).map { |i| { content_type_id: 2, _id: "c#{i}", title: "C#{i}" } }
        targets + [{ content_type_id: 2, _id: 'a', title: 'A' },
                   { content_type_id: 2, _id: 'x', title: 'X' }]
      end

      it 'serves it from the cache instead of the store' do
        window = preloaded_window

        window[0].articles.all
        allow(adapter).to receive(:make_id).and_call_original

        expect(window[1].articles.all.map(&:title)).to eq %w(X A)
        expect(target_queries).to eq 2
        expect(adapter).to have_received(:make_id).with('a').once
      end

    end

    context 'a composite component across the fallback boundary' do

      let(:entries) do
        [{ content_type_id: 1, _id: 'u1', name: 'One',
           article_ids: ['aaaabbbbccccddddeeee0001', 'h1', 'h2', 'compx', 'y'] }]
      end
      let(:other_entries) do
        [{ content_type_id: 2, _id: ['aaaabbbbccccddddeeee0001', 'compx'], _slug: 'compx', title: 'X' },
         { content_type_id: 2, _id: 'h1', title: 'H1', _visible: false },
         { content_type_id: 2, _id: 'h2', title: 'H2', _visible: false },
         { content_type_id: 2, _id: 'y', title: 'Y' }]
      end

      it 'fills the window past an already answered component' do
        window = preloaded_window

        expect(window[0].articles.load_window(nil, 0, 2).map(&:title)).to eq %w(X Y)
      end

    end

    context 'a large owner behind an already cached prefix' do

      let(:entries) do
        [
          { content_type_id: 1, _id: 'u1', name: 'One', article_ids: ['a', 'b'] },
          { content_type_id: 1, _id: 'u2', name: 'Two', article_ids: ['a', 'b'] + 1.upto(150).map { |i| "big#{i}" } }
        ]
      end
      let(:other_entries) do
        targets = 1.upto(150).map { |i| { content_type_id: 2, _id: "big#{i}", title: "Big#{i}" } }
        targets + [{ content_type_id: 2, _id: 'a', title: 'A' },
                   { content_type_id: 2, _id: 'b', title: 'B' }]
      end

      it 'serves the prefix from the cache and continues at the first unresolved ID' do
        window = preloaded_window

        expect(window[0].articles.all.map(&:title)).to eq %w(A B)

        allow(adapter).to receive(:make_id).and_call_original
        titles = window[1].articles.all.map(&:title)

        expect(titles).to eq %w(A B) + 1.upto(150).map { |i| "Big#{i}" }
        expect(target_queries).to eq 2
        expect(adapter).to have_received(:make_id).with('a').once
      end

    end

    context 'one more owner than the ID budget covers' do

      let(:entries) do
        1.upto(101).map { |i| { content_type_id: 1, _id: "u#{i}", name: "O#{i}", article_ids: ["t#{i}"] } }
      end
      let(:other_entries) do
        1.upto(101).map { |i| { content_type_id: 2, _id: "t#{i}", title: "t#{i}" } }
      end

      it 'costs one continuation, never one query per owner' do
        window = preloaded_window

        expect(window.map { |owner| owner.articles.all.map(&:title) })
          .to eq 1.upto(101).map { |i| ["t#{i}"] }
        window[99].articles.all

        expect(target_queries).to eq 4
      end

    end

    context 'a refill resumed by a later batch' do

      let(:entries) do
        [
          { content_type_id: 1, _id: 'u1', name: 'One', article_ids: ['h1', 'a'] },
          { content_type_id: 1, _id: 'u2', name: 'Two', article_ids: ['x'] }
        ]
      end
      let(:other_entries) do
        [
          { content_type_id: 2, _id: 'h1', title: 'H1', _visible: false },
          { content_type_id: 2, _id: 'a',  title: 'A' },
          { content_type_id: 2, _id: 'x',  title: 'X' }
        ]
      end

      it 'lets a later batch pick up where the refill stopped' do
        window = preloaded_window

        expect(window[0].articles.load_window(nil, 0, 1).map(&:title)).to eq %w(A)
        expect(window[1].articles.load_window(nil, 0, 1).map(&:title)).to eq %w(X)
        expect(window[0].articles.load_window(nil, 0, 2).map(&:title)).to eq %w(A)

        expect(target_queries).to eq 3
      end

    end

    context 'a window sweep with an offset' do

      let(:entries) do
        [
          { content_type_id: 1, _id: 'u1', name: 'One',   article_ids: ['a', 'b'] },
          { content_type_id: 1, _id: 'u2', name: 'Two',   article_ids: ['c', 'd'] },
          { content_type_id: 1, _id: 'u3', name: 'Three', article_ids: ['e', 'f'] }
        ]
      end
      let(:other_entries) do
        %w(a b c d e f).map { |id| { content_type_id: 2, _id: id, title: id.upcase } }
      end

      it 'prefetches the whole candidate prefix of the window shape' do
        window = preloaded_window

        expect(window.map { |author| author.articles.load_window(nil, 1, 1).map(&:title) })
          .to eq [%w(B), %w(D), %w(F)]
        expect(target_queries).to eq 2
      end

    end

    context 'a hidden head with a long tail' do

      let(:entries) { [{ content_type_id: 1, _id: 'u1', name: 'One', article_ids: 1.upto(20).map { |i| "gone#{i}" } + ['a'] }] }
      let(:other_entries) do
        targets = 1.upto(20).map { |i| { content_type_id: 2, _id: "gone#{i}", title: "Gone#{i}", _visible: false } }
        targets << { content_type_id: 2, _id: 'a', title: 'A' }
      end

      it 'continues through the repository without re-reading the prefix' do
        window = preloaded_window
        allow(adapter).to receive(:make_id).and_call_original

        expect(window[0].articles.load_window(nil, 0, 1).map(&:title)).to eq %w(A)
        expect(target_queries).to eq 2
        expect(adapter).to have_received(:make_id).with('gone1').twice
      end

    end

    context 'a hidden target heads the sequence' do

      let(:other_entries) do
        [
          { content_type_id: 2, _id: 'a', title: 'A' },
          { content_type_id: 2, _id: 'b', title: 'B', _visible: false },
          { content_type_id: 2, _id: 'c', title: 'C' }
        ]
      end

      it 'yields its place to the next candidate' do
        window = preloaded_window

        expect(window[0].articles.load_window(nil, 0, 1).map(&:title)).to eq %w(A)
      end

    end

    context 'an owner larger than the cache limit' do

      let(:entries) do
        [
          { content_type_id: 1, _id: 'u1', name: 'One', article_ids: 1.upto(150).map { |i| "big#{i}" } },
          { content_type_id: 1, _id: 'u2', name: 'Two', article_ids: ['a'] }
        ]
      end
      let(:other_entries) do
        targets = 1.upto(150).map { |i| { content_type_id: 2, _id: "big#{i}", title: "Big#{i}" } }
        targets << { content_type_id: 2, _id: 'a', title: 'A' }
      end

      it 'reads through the repository and keeps the cache for the others' do
        window = preloaded_window

        expect(window[0].articles.all.length).to eq 150
        expect(window[1].articles.all.map(&:title)).to eq %w(A)
        expect(target_queries).to eq 2
      end

      it 'normalizes only the candidate prefix of a window' do
        window = preloaded_window
        allow(adapter).to receive(:make_id).and_call_original

        window[0].articles.load_window(nil, 0, 1)

        expect(adapter).to have_received(:make_id).with('big1').at_least(:once)
        expect(adapter).not_to have_received(:make_id).with('big2')
      end

      it 'windows a large owner instead of falling back' do
        window = preloaded_window

        expect(window[0].articles.load_window(nil, 0, 1).map(&:title)).to eq %w(Big1)
        expect(window[0].articles.load_window(nil, 0, 1).map(&:title)).to eq %w(Big1)
        expect(target_queries).to eq 1
      end

    end

    it 'enumerates through the preloader and feeds its cache' do
      window = preloaded_window

      titles = []
      window[0].articles.each { |article| titles << article.title }

      expect(titles).to eq %w(B A)
      expect(window[0].articles.all.map(&:title)).to eq %w(B A)
      expect(target_queries).to eq 1
    end

    it 'keeps a runtime-scoped read on the per-parent path, outside the cache' do
      window = preloaded_window

      expect(window[0].articles.all.map(&:title)).to eq %w(B A)
      expect(target_queries).to eq 1

      scoped = repository.value_for(window[0], :articles, order_by: 'title.asc')

      expect(scoped.all.map(&:title)).to eq %w(A B)
      expect(target_queries).to eq 2

      expect(window[0].articles.all.map(&:title)).to eq %w(B A)
      expect(target_queries).to eq 2
    end

    it 'serves first from the window without reading past the heads' do
      window = preloaded_window

      expect(window[0].articles.first.title).to eq 'B'
      expect(window[1].articles.first.title).to eq 'A'
      expect(window[2].articles.first.title).to eq 'D'
      expect(target_queries).to eq 2

      expect(window[1].articles.all.map(&:title)).to eq %w(A C)
      expect(target_queries).to eq 3
    end

    it 'leaves first with conditions or a block on the repository path' do
      window = preloaded_window

      expect(window[0].articles.first(title: 'A').title).to eq 'A'
      expect(target_queries).to eq 1

      expect(window[0].articles.first { offset(1) }.title).to eq 'A'
      expect(target_queries).to eq 2
    end

    it 'leaves count and exists on the repository path' do
      window = preloaded_window

      expect(window[0].articles.count).to eq 2
      expect(window[0].articles.exists?).to be true

      window[0].articles.all
      expect(target_queries).to eq 3
    end

    context 'the field declares its own order' do

      let(:field) { instance_double('Field', name: :articles, type: :many_to_many, association_options: { target_id: 2, inverse_of: :authors, order_by: 'title.asc' }) }

      it 'stays on the repository path' do
        window = preloaded_window

        expect(window[0].articles.all.map(&:title)).to eq %w(A B)
        expect(window[1].articles.all.map(&:title)).to eq %w(A C)
        expect(target_queries).to eq 2
      end

    end

    context 'a sequence holding null and unanswered ids' do

      let(:entries) do
        [
          { content_type_id: 1, _id: 'u1', name: 'One', article_ids: [nil, 'b', 'ghost', 'a'] },
          { content_type_id: 1, _id: 'u2', name: 'Two', article_ids: ['a', 'c'] }
        ]
      end

      it 'skips them without touching the other owners' do
        window = preloaded_window

        expect(window[0].articles.all.map(&:title)).to eq %w(B A)
        expect(window[1].articles.all.map(&:title)).to eq %w(A C)
      end

    end

  end

end
