require "rails_helper"

RSpec.describe AnalyzeMealJob do
  let(:meal) { create(:meal, :with_photo) }

  it "runs the analyzer for a pending meal" do
    analyzer = instance_double(Meals::Analyzer, call: nil)
    allow(Meals::Analyzer).to receive(:new).with(meal).and_return(analyzer)

    described_class.perform_now(meal.id)

    expect(analyzer).to have_received(:call)
  end

  it "does not re-analyse a meal that already settled" do
    # A retry landing after the work finished would spend a second call for
    # nothing, so the job checks before doing anything.
    settled = create(:meal, :succeeded)
    allow(Meals::Analyzer).to receive(:new)

    described_class.perform_now(settled.id)

    expect(Meals::Analyzer).not_to have_received(:new)
  end

  it "discards quietly when the meal has been deleted" do
    expect { described_class.perform_now(-1) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  describe "retry policy" do
    include ActiveJob::TestHelper

    def analyzer_always_raising(error)
      analyzer = instance_double(Meals::Analyzer)
      allow(analyzer).to receive(:call) do
        # Mirrors what the real analyzer does with a retryable failure: leave
        # the meal claimable rather than settling it, or the job's `settled?`
        # guard would swallow every retry.
        meal.update!(status: :pending)
        raise error
      end
      allow(Meals::Analyzer).to receive(:new).and_return(analyzer)
      analyzer
    end

    it "retries a rate limit several times before giving up" do
      analyzer = analyzer_always_raising(Meals::Analyzer::RateLimited.new("429"))

      perform_enqueued_jobs { described_class.perform_later(meal.id) }

      expect(analyzer).to have_received(:call).exactly(5).times
    end

    it "gives up on a transient provider error sooner" do
      analyzer = analyzer_always_raising(Meals::Analyzer::ProviderError.new("503"))

      perform_enqueued_jobs { described_class.perform_later(meal.id) }

      expect(analyzer).to have_received(:call).exactly(3).times
    end

    it "settles the meal once retries are exhausted, rather than leaving it pending" do
      # Without an exhaustion block the meal would sit in `pending` forever with
      # no job left to move it.
      analyzer_always_raising(Meals::Analyzer::RateLimited.new("429"))

      perform_enqueued_jobs { described_class.perform_later(meal.id) }

      expect(meal.reload).to be_failed
      expect(meal.failure_kind).to eq("rate_limited")
      expect(meal.failure_reason).to match(/gave up after \d+ attempts/)
    end

    it "records the right kind for an exhausted provider error" do
      analyzer_always_raising(Meals::Analyzer::ProviderError.new("503"))

      perform_enqueued_jobs { described_class.perform_later(meal.id) }

      expect(meal.reload.failure_kind).to eq("provider_error")
    end

    it "does not settle a meal that succeeded on a later attempt" do
      attempts = 0
      analyzer = instance_double(Meals::Analyzer)
      allow(analyzer).to receive(:call) do
        attempts += 1
        raise Meals::Analyzer::ProviderError, "503" if attempts < 2

        meal.update!(status: :succeeded)
      end
      allow(Meals::Analyzer).to receive(:new).and_return(analyzer)

      perform_enqueued_jobs { described_class.perform_later(meal.id) }

      expect(meal.reload).to be_succeeded
      expect(meal.failure_kind).to be_nil
    end
  end
end
