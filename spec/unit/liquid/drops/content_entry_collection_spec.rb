require 'spec_helper'

describe Locomotive::Steam::Liquid::Drops::ContentEntryCollection do

  let(:assigns)       { {} }
  let(:content_type)  { instance_double('ContentType', slug: 'articles') }
  let(:services)      { Locomotive::Steam::Services.build_instance }
  let(:context)       { ::Liquid::Context.new(assigns, {}, { services: services, locale: :en }) }
  let(:drop)          { described_class.new(content_type).tap { |d| d.context = context } }

  before { allow(services).to receive(:current_site).and_return(nil) }

  describe '#public_submission_url' do
    it { expect(drop.public_submission_url).to eq '/entry_submissions/articles' }
  end

  describe '#api' do
    it { expect(drop.api).to eq({ 'create' => '/entry_submissions/articles' }) }
  end

  describe 'acts as a collection' do

    let(:repo) { services.repositories.content_entry }

    describe '#first' do
      it 'pushes down to repository.first, not #all' do
        allow(repo).to receive(:first).with(nil).and_return('a')
        allow(repo).to receive(:all)
        expect(drop.first).to eq('a')
        expect(repo).not_to have_received(:all)
      end
    end

    describe '#first(n)' do
      it 'materializes and slices the collection' do
        allow(repo).to receive(:all).with(nil).and_return(['a', 'b'])
        expect(drop.first(2)).to eq(['a', 'b'])
      end
    end

    describe '#last' do
      before { allow(repo).to receive(:all).with(nil).and_return(['a', 'b']) }
      it { expect(drop.last).to eq('b') }
    end

    describe '#map' do
      before { allow(repo).to receive(:all).with(nil).and_return(['a', 'b']) }
      it { expect(drop.map(&:to_s)).to eq(['a', 'b']) }
    end

    # Liquid slices a collection through #load_slice, passing an end index rather
    # than a length, and nil when the loop only skips.
    describe '#load_slice' do

      let(:window) do
        Class.new do
          attr_reader :window
          def initialize; @window = {}; end
          def offset(value); @window[:offset] = value; self; end
          def limit(value);  @window[:limit]  = value; self; end
        end.new
      end

      before do
        allow(repo).to receive(:all) do |_conditions, &block|
          window.instance_exec(&block)
          ['a', 'b']
        end
      end

      it 'turns the end index into a length the query can take' do
        expect(drop.load_slice(0, 2)).to eq(['a', 'b'])
        expect(window.window).to eq(offset: 0, limit: 2)
      end

      it 'offsets without limiting when there is no end index' do
        drop.load_slice(5, nil)
        expect(window.window).to eq(offset: 5, limit: nil)
      end

      it 'keeps the offset out of the length' do
        drop.load_slice(10, 15)
        expect(window.window).to eq(offset: 10, limit: 5)
      end

      it 'asks for nothing rather than a negative length' do
        drop.load_slice(10, 4)
        expect(window.window).to eq(offset: 10, limit: 0)
      end

      it 'starts at the beginning rather than before it' do
        drop.load_slice(-1, nil)
        expect(window.window).to eq(offset: 0, limit: nil)
      end

      it 'measures the length from the beginning it settled on' do
        drop.load_slice(-1, 1)
        expect(window.window).to eq(offset: 0, limit: 1)
      end

      it 'asks for nothing when the end index is the beginning' do
        drop.load_slice(-1, 0)
        expect(window.window).to eq(offset: 0, limit: 0)
      end

      it 'keeps a window the store cannot take inside the range it can' do
        drop.load_slice(2**64, 2**65)
        expect(window.window).to eq(offset: 2**63 - 1, limit: 2**63 - 1)
      end

      describe 'on a materialized collection' do

        before do
          allow(repo).to receive(:all).with(nil).and_return(%w(a b c d))
          drop.map { |entry| entry }
        end

        it 'slices it instead of querying again' do
          expect(repo).not_to receive(:all)
          expect(drop.load_slice(1, 3)).to eq(%w(b c))
          expect(drop.load_slice(2, nil)).to eq(%w(c d))
          expect(drop.load_slice(9, 12)).to eq([])
        end

        # Ruby would read a negative index from the end, which is not what the
        # loop asked for and not what the store would have answered.
        it 'answers a window before the beginning the way the store would' do
          expect(drop.load_slice(-1, nil)).to eq(%w(a b c d))
          expect(drop.load_slice(-1, 1)).to eq(%w(a))
          expect(drop.load_slice(-1, 0)).to eq([])
        end

      end

    end

    describe '#empty?' do
      it 'pushes down to repository.exists?, not #all' do
        allow(repo).to receive(:exists?).with(nil).and_return(false)
        allow(repo).to receive(:all)
        expect(drop.empty?).to eq true
        expect(repo).not_to have_received(:all)
      end

      it 'is false when the collection has entries' do
        allow(repo).to receive(:exists?).with(nil).and_return(true)
        expect(drop.empty?).to eq false
      end
    end

    describe '#any?' do
      it 'without a block pushes down to repository.exists?, not #all' do
        allow(repo).to receive(:exists?).with(nil).and_return(true)
        allow(repo).to receive(:all)
        expect(drop.any?).to eq true
        expect(repo).not_to have_received(:all)
      end

      it 'with a block materializes and evaluates it (Array#any? contract)' do
        allow(repo).to receive(:all).with(nil).and_return(['a', 'b'])
        expect(drop.any? { |e| e == 'a' }).to eq true
      end

      it 'with a pattern argument materializes and evaluates it' do
        allow(repo).to receive(:all).with(nil).and_return(['a', 'b'])
        expect(drop.any?('a')).to eq true
      end
    end

    describe 'reusing an already-materialized collection' do
      it 'first/empty?/any? read the loaded collection without re-querying' do
        allow(repo).to receive(:all).with(nil).and_return(['a', 'b'])
        drop.map { |e| e }

        expect(repo).not_to receive(:first)
        expect(repo).not_to receive(:exists?)
        expect(drop.first).to eq('a')
        expect(drop.empty?).to eq false
        expect(drop.any?).to eq true
      end
    end

    context 'with a scope' do

      let(:assigns) { { 'with_scope' => { 'visible' => true } } }

      describe '#first' do
        before { expect(repo).to receive(:first).with({ 'visible' => true }).and_return('a') }
        it { expect(drop.first).to eq('a') }
      end

      describe '#count' do
        before { expect(repo).to receive(:count).with({ 'visible' => true }).and_return(2) }
        it { expect(drop.count).to eq 2 }
      end

      describe 'only applied to the first content type' do

        it 'sets the content type in the context' do
          expect(repo).to receive(:first).with({ 'visible' => true }).and_return('a')
          expect(context['with_scope_content_type']).to eq nil
          drop.first
          expect(context['with_scope_content_type']).to eq 'articles'
        end

        it "doesn't apply the with_scope conditions if it's not the same content type" do
          context['with_scope_content_type'] = 'projects'
          expect(repo).to receive(:first).with({}).and_return('a')
          drop.first
          expect(context['with_scope_content_type']).to eq 'projects'
        end

      end

    end

  end

  describe 'get options of a select field' do

    let(:option_a) { build_select_option(en: 'a') }
    let(:option_b) { build_select_option('b') }

    before do
      expect(services.repositories.content_type).to receive(:select_options).with(content_type, 'category').and_return([option_a, option_b])
    end

    it { expect(drop.liquid_method_missing(:category_options)).to eq ['a', 'b'] }

  end

  describe 'group entries by a select/belongs_to field' do

    before do
      expect(services.repositories.content_entry).to receive(:group_by_select_option).with('category').and_return([['a', [1, 2]]])
    end

    it { expect(drop.liquid_method_missing(:group_by_category)).to eq [['a', [1, 2]]] }

  end

  describe 'unknown method' do

    it { expect(drop.liquid_method_missing(:foo)).to eq nil }

  end

  def build_select_option(name)
    _name = Locomotive::Steam::Models::I18nField.new('name', name)
    Locomotive::Steam::ContentTypeField::SelectOption.new(name: _name).tap do |option|
      option.localized_attributes = [:name]
    end
  end

end
