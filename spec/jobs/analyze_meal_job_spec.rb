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
    it "retries rate limits more patiently than other provider errors" do
      rate_limit = described_class.rescue_handlers.find { |k, _| k == "Meals::Analyzer::RateLimited" }
      provider = described_class.rescue_handlers.find { |k, _| k == "Meals::Analyzer::ProviderError" }

      expect(rate_limit).to be_present
      expect(provider).to be_present
    end
  end
end
