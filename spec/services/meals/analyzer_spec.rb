require "rails_helper"

RSpec.describe Meals::Analyzer do
  subject(:analyzer) { described_class.new(meal) }

  let(:meal) { create(:meal, :with_photo) }
  let(:apple_payload) do
    {
      "food_detected" => true,
      "notes" => "Scale taken from the plate.",
      "items" => [
        { "name" => "Apple", "grams" => 182, "kcal" => 95,
          "protein_g" => 0.5, "carbs_g" => 25.1, "fat_g" => 0.3, "confidence" => 0.92 }
      ]
    }
  end

  # A stand-in for ruby_llm's response object. The provider round trip is
  # exercised separately via a cassette; these specs are about what the analyzer
  # does with a reply once it has one.
  def response(content, input_tokens: 900, output_tokens: 120)
    instance_double(
      RubyLLM::Message,
      content: content,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      model_id: "gemini-3.6-flash"
    )
  end

  def chat_double(*responses)
    chat = instance_double(RubyLLM::Chat)
    allow(chat).to receive_messages(with_instructions: chat, with_schema: chat)
    allow(chat).to receive(:ask).and_return(*responses) if responses.any?
    allow(RubyLLM).to receive(:chat).and_return(chat)
    chat
  end


  describe "a plausible extraction" do
    before { chat_double(response(apple_payload)) }

    it "marks the meal succeeded" do
      analyzer.call

      expect(meal.reload).to be_succeeded
    end

    it "persists the item as reported" do
      analyzer.call
      item = meal.reload.items.sole

      expect(item).to have_attributes(
        food_name: "Apple",
        grams: BigDecimal("182"),
        kcal: BigDecimal("95"),
        confidence: BigDecimal("0.92")
      )
    end

    it "also stores the per-100g basis that makes the record reusable" do
      analyzer.call

      expect(meal.reload.items.sole.kcal_per_100g).to eq(BigDecimal("52.2"))
    end

    it "records which model produced it, and what it cost" do
      analyzer.call

      expect(meal.reload).to have_attributes(
        model_id: LlmConfig.model,
        input_tokens: 900,
        output_tokens: 120
      )
      expect(meal.analyzed_at).to be_present
      expect(meal.latency_ms).to be >= 0
    end

    it "keeps the raw payload for debugging" do
      analyzer.call

      expect(meal.reload.raw_response).to eq(apple_payload)
    end
  end

  describe "a photo with no food in it" do
    before do
      chat_double(response({ "food_detected" => false, "items" => [], "notes" => "A bicycle." }))
    end

    it "is an answer, not a failure" do
      analyzer.call

      expect(meal.reload).to be_not_food
      expect(meal.failure_kind).to be_nil
    end

    it "stores no items" do
      analyzer.call

      expect(meal.reload.items).to be_empty
    end
  end

  describe "an implausible extraction" do
    # Well-formed against the schema, and nutritionally impossible. This is the
    # case the schema cannot catch on its own.
    let(:impossible) do
      { "food_detected" => true,
        "items" => [ { "name" => "Lettuce", "grams" => 20, "kcal" => 2000,
                     "protein_g" => 1, "carbs_g" => 1, "fat_g" => 1, "confidence" => 0.99 } ] }
    end

    it "asks the model to correct itself, and accepts the correction" do
      chat = chat_double(response(impossible), response(apple_payload))
      analyzer.call

      expect(chat).to have_received(:ask).twice
      expect(meal.reload).to be_succeeded
    end

    it "gives up after one repair attempt rather than looping" do
      chat = chat_double(response(impossible), response(impossible))
      analyzer.call

      expect(chat).to have_received(:ask).twice
      expect(meal.reload).to be_failed
      expect(meal.failure_kind).to eq("invalid_extraction")
    end

    it "records why it was rejected" do
      chat_double(response(impossible), response(impossible))
      analyzer.call

      expect(meal.reload.failure_reason).to match(/does not match its macros|above the 900/)
    end

    it "keeps the rejected payload so it can be inspected" do
      chat_double(response(impossible), response(impossible))
      analyzer.call

      expect(meal.reload.raw_response).to eq(impossible)
    end

    it "stores no items from a rejected extraction" do
      chat_double(response(impossible), response(impossible))
      analyzer.call

      expect(meal.reload.items).to be_empty
    end
  end

  describe "provider failures" do
    # Retryable failures propagate so AnalyzeMealJob's retry_on can act on them.
    # They are deliberately NOT recorded as failed here: `failed` counts as
    # settled, and the job skips settled meals, which would kill the retry.
    it "re-raises a rate limit for the job to retry" do
      chat_double
      allow(RubyLLM.chat).to receive(:ask).and_raise(RubyLLM::RateLimitError.new("429"))

      expect { analyzer.call }.to raise_error(described_class::RateLimited)
    end

    it "leaves the meal claimable after a retryable failure" do
      chat_double
      allow(RubyLLM.chat).to receive(:ask).and_raise(RubyLLM::RateLimitError.new("429"))

      suppress(described_class::RateLimited) { analyzer.call }

      expect(meal.reload).to be_pending
    end

    it "re-raises a server error for the job to retry" do
      chat_double
      allow(RubyLLM.chat).to receive(:ask).and_raise(RubyLLM::ServerError.new("503"))

      expect { analyzer.call }.to raise_error(described_class::ProviderError)
    end

    it "re-raises a timeout for the job to retry" do
      chat_double
      allow(RubyLLM.chat).to receive(:ask).and_raise(Faraday::TimeoutError.new("execution expired"))

      expect { analyzer.call }.to raise_error(described_class::ProviderError, /TimeoutError/)
    end

    it "treats a malformed request as terminal, since retrying repeats it" do
      chat_double
      allow(RubyLLM.chat).to receive(:ask).and_raise(RubyLLM::BadRequestError.new("400"))

      analyzer.call

      expect(meal.reload.failure_kind).to eq("content_filtered")
    end

    it "records a missing API key rather than leaving the meal processing" do
      # RubyLLM::ConfigurationError subclasses StandardError, not
      # RubyLLM::Error -- the second of ruby_llm's two error families.
      chat_double
      allow(RubyLLM.chat).to receive(:ask).and_raise(RubyLLM::ConfigurationError.new("no key"))

      analyzer.call

      expect(meal.reload).to be_failed
      expect(meal.failure_kind).to eq("configuration_error")
    end

    it "classifies a bad credential as a configuration problem, not a retryable one" do
      chat_double
      allow(RubyLLM.chat).to receive(:ask).and_raise(RubyLLM::UnauthorizedError.new("401"))

      analyzer.call

      expect(meal.reload.failure_kind).to eq("configuration_error")
    end

    it "records an unknown model instead of leaving the meal stuck processing" do
      # ModelNotFoundError subclasses StandardError rather than RubyLLM::Error,
      # so it slips past a rescue chain built around RubyLLM::Error and strands
      # the record mid-flight. Raised at chat construction, before any request.
      allow(RubyLLM).to receive(:chat).and_raise(
        RubyLLM::ModelNotFoundError.new("Unknown model: \"gemini-9-flash\"")
      )

      analyzer.call

      expect(meal.reload).to be_failed
      expect(meal.failure_kind).to eq("configuration_error")
      expect(meal.failure_reason).to include("Unknown model")
    end

    it "never leaves a meal in processing, whatever goes wrong" do
      allow(RubyLLM).to receive(:chat).and_raise(RubyLLM::ModelNotFoundError.new("nope"))

      analyzer.call

      expect(meal.reload).not_to be_processing
    end
  end

  describe "model selection" do
    it "validates the model against the registry by default" do
      chat_double(response(apple_payload))

      analyzer.call

      expect(RubyLLM).to have_received(:chat).with(model: LlmConfig.model)
    end

    it "skips registry validation when a provider is named" do
      # Lets a model newer than the installed ruby_llm be used without waiting
      # for a gem release.
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("LLM_PROVIDER").and_return("gemini")
      chat_double(response(apple_payload))

      described_class.new(meal, model: "gemini-3.6-flash").call

      expect(RubyLLM).to have_received(:chat).with(
        model: "gemini-3.6-flash", provider: :gemini, assume_model_exists: true
      )
    end
  end

  it "marks the meal processing while the call is in flight" do
    chat = instance_double(RubyLLM::Chat)
    allow(chat).to receive_messages(with_instructions: chat, with_schema: chat)
    allow(RubyLLM).to receive(:chat).and_return(chat)
    allow(chat).to receive(:ask) do
      expect(meal.reload).to be_processing
      response(apple_payload)
    end

    analyzer.call
  end
end
