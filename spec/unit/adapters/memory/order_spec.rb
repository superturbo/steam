require 'spec_helper'

require_relative '../../../../lib/locomotive/steam/adapters/memory/order.rb'

describe Locomotive::Steam::Adapters::Memory::Order do

  let(:order) { Locomotive::Steam::Adapters::Memory::Order.new(*input) }

  describe '#list' do

    subject { order.list }

    let(:input) { nil }
    it { is_expected.to eq [] }

    context 'via a string' do

      let(:input) { 'name DESC' }
      it { is_expected.to eq [[:name, :desc]] }

    end

    context 'via a hash with symbol directions' do

      let(:input) { [{ name: :asc, date: :desc }] }
      it { is_expected.to eq [[:name, :asc], [:date, :desc]] }

    end

    context 'via a string' do

      let(:input) { 'name ASC, date DESC' }
      it { is_expected.to eq [[:name, :asc], [:date, :desc]] }

    end

  end

  describe 'a Mongo operator field' do
    it 'is rejected through the shared decoder' do
      expect { described_class.new('$natural') }.to raise_error(Locomotive::Steam::Adapters::Query::UnsupportedOperator)
    end
  end

  describe '#apply_to' do

    subject { order.apply_to(entry, :en) }

    let(:input) { 'title asc, date desc' }
    let(:entry) { instance_double('Entry', title: 'foo', date: Time.zone.now) }
    it { expect(subject.map(&:class)).to eq([Locomotive::Steam::Adapters::Memory::Order::Asc, Locomotive::Steam::Adapters::Memory::Order::Desc]) }

    context 'localized field' do

      let(:now)   { Time.zone.now }
      let(:field) { instance_double('TitleI18nField', :[] => 'Hello world', translations: true) }
      let(:entry) { instance_double('Entry', title: field, date: now) }
      it { expect(subject.map(&:obj)).to eq(['Hello world', now]) }

    end

  end

  describe 'sort' do

    let(:array) {
      [
        instance_double('Entry1', id: 1, title: 'b', position: 1),
        instance_double('Entry2', id: 2, title: 'b', position: 2),
        instance_double('Entry3', id: 3, title: 'a', position: 3),
        instance_double('Entry3', id: 4, title: 'c', position: 1)
      ]
    }
    let(:input) { 'title asc, position desc' }

    subject { array.sort_by { |entry| order.apply_to(entry, :en) } }

    it { expect(subject.map(&:id)).to eq([3, 2, 1, 4]) }

    context 'nil value in the array' do

      let(:array) {
        [
          instance_double('Entry1', id: 1, title: 'b', position: 1),
          instance_double('Entry2', id: 2, title: 'b', position: 2),
          instance_double('Entry3', id: 3, title: nil, position: 3),
          instance_double('Entry3', id: 4, title: 'c', position: 1)
        ]
      }

      # MongoDB sorts null below strings, so it leads ascending
      it { expect(subject.map(&:id)).to eq([3, 2, 1, 4]) }

    end

    context 'a nil value descending' do

      let(:input) { 'title desc' }
      let(:array) {
        [
          instance_double('Entry1', id: 1, title: 'b'),
          instance_double('Entry2', id: 2, title: nil),
          instance_double('Entry3', id: 3, title: 'c')
        ]
      }

      it { expect(subject.map(&:id)).to eq([3, 1, 2]) }

    end

    context 'a nil first key' do

      let(:input) { 'title asc, position asc' }
      let(:array) {
        [
          instance_double('Entry1', id: 1, title: nil, position: 3),
          instance_double('Entry2', id: 2, title: nil, position: 1),
          instance_double('Entry3', id: 3, title: nil, position: 2)
        ]
      }

      # nil <=> nil has to be a tie, or Array#<=> stops at the first key
      it 'still applies the secondary key' do
        expect(subject.map(&:id)).to eq([2, 3, 1])
      end

    end

    context 'a boolean field' do

      let(:input) { 'featured asc, position asc' }
      let(:array) {
        [
          instance_double('Entry1', id: 1, featured: true,  position: 1),
          instance_double('Entry2', id: 2, featured: false, position: 2),
          instance_double('Entry3', id: 3, featured: false, position: 1)
        ]
      }

      it 'sorts false before true, and does not read false as null' do
        expect(subject.map(&:id)).to eq([3, 2, 1])
      end

    end

    context 'a field the entity does not carry' do

      let(:input) { 'notes asc, title asc' }
      let(:array) {
        [
          instance_double('Entry1', id: 1, title: 'b'),
          instance_double('Entry2', id: 2, title: 'a')
        ]
      }

      it 'sorts it as null instead of raising' do
        expect(subject.map(&:id)).to eq([2, 1])
      end

    end

    context 'a column holding several types' do

      let(:input) { 'title asc' }
      let(:array) {
        [
          instance_double('Entry1', id: 1, title: 'b'),
          instance_double('Entry2', id: 2, title: 5)
        ]
      }

      it 'rejects values Ruby cannot compare' do
        expect { subject }.to raise_error(ArgumentError)
      end

    end

  end

end
