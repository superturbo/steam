require 'spec_helper'

require_relative '../../../../lib/locomotive/steam/middlewares/concerns/recaptcha'

describe Locomotive::Steam::Middlewares::Concerns::Recaptcha do

  let(:middleware_class) { Class.new { include Locomotive::Steam::Middlewares::Concerns::Recaptcha } }
  let(:instance)         { middleware_class.new }

  let(:metafields)        { {} }
  let(:site)              { instance_double('Site', domains: ['example.com'], metafields: { google: metafields }) }
  let(:recaptcha_enabled) { false }
  let(:content_type)      { instance_double('ContentType', recaptcha_required?: recaptcha_enabled) }
  let(:entry_service)     { instance_double('EntryService', get_type: content_type, build: entry) }
  let(:verify_response)   { {} }
  let(:recaptcha_service) { instance_double('RecaptchaService', verify: verify_response) }
  let(:services)          { instance_double('Services', recaptcha: recaptcha_service, content_entry: entry_service) }
  let(:liquid_assigns)    { {} }
  let(:entry)             { instance_double('Entry', errors: instance_double('Errors', add: true)) }

  before do
    allow(instance).to receive(:site).and_return(site)
    allow(instance).to receive(:services).and_return(services)
    allow(instance).to receive(:liquid_assigns).and_return(liquid_assigns)
    allow(instance).to receive(:log)
  end

  describe '#is_recaptcha_valid?' do

    let(:slug)          { 'contacts' }
    let(:response_code) { 'token123' }

    subject { instance.is_recaptcha_valid?(slug, response_code) }

    context 'when recaptcha is not required' do

      it { is_expected.to eq true }

      it 'does not call the recaptcha service' do
        subject
        expect(recaptcha_service).not_to have_received(:verify)
      end

    end

    context 'when recaptcha is required' do

      let(:recaptcha_enabled) { true }

      context 'with a valid response' do

        let(:verify_response) { { 'success' => true, 'hostname' => 'example.com', 'action' => 'contacts', 'score' => 0.9 } }

        it { is_expected.to eq true }

        it 'sets recaptcha_invalid to false' do
          subject
          expect(liquid_assigns['recaptcha_invalid']).to eq false
        end

      end

      context 'when success is false' do

        let(:verify_response) { { 'success' => false, 'hostname' => 'example.com', 'action' => 'contacts' } }

        it { is_expected.to eq false }

        it 'sets recaptcha_invalid to true' do
          subject
          expect(liquid_assigns['recaptcha_invalid']).to eq true
        end

      end

      context 'when hostname does not match site domains' do

        let(:verify_response) { { 'success' => true, 'hostname' => 'evil.com', 'action' => 'contacts' } }

        it { is_expected.to eq false }

      end

      context 'when action does not match the slug' do

        let(:verify_response) { { 'success' => true, 'hostname' => 'example.com', 'action' => 'wrong_slug' } }

        it { is_expected.to eq false }

      end

      context 'when error-codes are present' do

        let(:verify_response) { { 'success' => true, 'hostname' => 'example.com', 'action' => 'contacts', 'error-codes' => ['invalid-input-response'] } }

        it { is_expected.to eq false }

      end

      context 'when details are empty (blank response_code)' do

        let(:verify_response) { {} }

        it { is_expected.to eq false }

        it 'does not raise' do
          expect { subject }.not_to raise_error
        end

      end

      context 'with score threshold configured' do

        let(:metafields) { { recaptcha_score_threshold: '0.5' } }

        context 'when score is above threshold' do

          let(:verify_response) { { 'success' => true, 'hostname' => 'example.com', 'action' => 'contacts', 'score' => 0.9 } }

          it { is_expected.to eq true }

        end

        context 'when score is below threshold' do

          let(:verify_response) { { 'success' => true, 'hostname' => 'example.com', 'action' => 'contacts', 'score' => 0.3 } }

          it { is_expected.to eq false }

        end

        context 'when score is absent' do

          let(:verify_response) { { 'success' => true, 'hostname' => 'example.com', 'action' => 'contacts' } }

          it { is_expected.to eq false }

        end

      end

    end

  end

  describe '#build_invalid_recaptcha_entry' do

    subject { instance.build_invalid_recaptcha_entry('contacts', { email: 'test@example.com' }) }

    it 'builds an entry and marks it as invalid' do
      expect(entry.errors).to receive(:add).with(:recaptcha_invalid, true)
      expect(subject).to eq entry
    end

  end

  describe '#recaptcha_score_threshold' do

    subject { instance.send(:recaptcha_score_threshold, metafields) }

    context 'with a valid float string' do
      let(:metafields) { { recaptcha_score_threshold: '0.5' } }
      it { is_expected.to eq 0.5 }
    end

    context 'with an integer value' do
      let(:metafields) { { recaptcha_score_threshold: 1 } }
      it { is_expected.to eq 1.0 }
    end

    context 'with an invalid string' do
      let(:metafields) { { recaptcha_score_threshold: 'bad' } }
      it { is_expected.to be_nil }
    end

    context 'with a nil value' do
      let(:metafields) { { recaptcha_score_threshold: nil } }
      it { is_expected.to be_nil }
    end

    context 'with a blank string' do
      let(:metafields) { { recaptcha_score_threshold: '' } }
      it { is_expected.to be_nil }
    end

  end

  describe '#recaptcha_score_valid?' do

    subject { instance.send(:recaptcha_score_valid?, score, threshold) }

    context 'when threshold is nil' do
      let(:score)     { 0.9 }
      let(:threshold) { nil }
      it { is_expected.to be_nil }
    end

    context 'when threshold is out of 0..1 range' do
      let(:score)     { 0.9 }
      let(:threshold) { 1.5 }
      it { is_expected.to be_nil }
    end

    context 'when score meets the threshold' do
      let(:score)     { 0.9 }
      let(:threshold) { 0.5 }
      it { is_expected.to eq true }
    end

    context 'when score is below the threshold' do
      let(:score)     { 0.3 }
      let(:threshold) { 0.5 }
      it { is_expected.to eq false }
    end

    context 'when score is nil' do
      let(:score)     { nil }
      let(:threshold) { 0.5 }
      it { is_expected.to eq false }
    end

  end

end
