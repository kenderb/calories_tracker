module Meals
  # Runs one meal photo through a vision model and turns the reply into
  # validated, persisted nutrition.
  #
  # The two layers of defence:
  #   1. NutritionSchema constrains the shape at the provider.
  #   2. Nutrition::Extraction checks the numbers describe a food that could
  #      exist. Only output that clears both is written to the database.
  #
  # When layer 2 rejects the reply, the analyzer takes exactly one repair turn,
  # handing the validation errors back to the same chat so the model can correct
  # itself in context. One, not a loop: if the model cannot fix an arithmetic
  # inconsistency it was just shown, another attempt buys nothing but latency.
  class Analyzer
    Result = Struct.new(:status, :extraction, :failure_kind, :failure_reason, keyword_init: true)

    MAX_REPAIR_ATTEMPTS = 1

    class ProviderError < StandardError; end
    class RateLimited < ProviderError; end
    class ContentFiltered < StandardError; end

    def initialize(meal, model: LlmConfig.model)
      @meal = meal
      @model = model
    end

    def call
      meal.update!(status: :processing)

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      extraction = extract
      latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

      persist(extraction, latency_ms)
    rescue RateLimited => e
      failure(:rate_limited, e.message)
    rescue ProviderError => e
      failure(:provider_error, e.message)
    rescue ContentFiltered => e
      failure(:content_filtered, e.message)
    end

    private

    attr_reader :meal, :model

    # Returns a valid Nutrition::Extraction, or raises. Never returns something
    # that failed validation.
    def extract
      chat = new_chat
      response = ask(chat) { chat.ask(Prompt::USER, with: meal.photo) }
      record_usage(response)

      extraction = Nutrition::Extraction.from_payload(response.content)
      return extraction if extraction.valid?

      MAX_REPAIR_ATTEMPTS.times do
        response = ask(chat) { chat.ask(repair_instruction(extraction)) }
        record_usage(response)

        extraction = Nutrition::Extraction.from_payload(response.content)
        break if extraction.valid?
      end

      extraction
    end

    def new_chat
      RubyLLM.chat(model: model)
             .with_instructions(Prompt::SYSTEM)
             .with_schema(NutritionSchema)
    end

    # Translates provider failures into the taxonomy the job layer retries on.
    def ask(_chat)
      yield
    rescue RubyLLM::RateLimitError => e
      raise RateLimited, e.message
    rescue RubyLLM::UnauthorizedError, RubyLLM::PaymentRequiredError => e
      # Not retryable: the key or the billing needs a human.
      raise ContentFiltered, e.message
    rescue RubyLLM::Error => e
      raise ProviderError, e.message
    rescue Faraday::TimeoutError, Net::ReadTimeout => e
      raise ProviderError, "timed out after #{LlmConfig.timeout}s: #{e.message}"
    end

    def repair_instruction(extraction)
      <<~TEXT
        Your previous answer did not pass validation:

        #{extraction.failure_summary}

        Calories must be consistent with the macronutrients you report: protein
        and carbohydrate are about 4 kcal per gram, fat about 9 kcal per gram.
        No food exceeds 900 kcal per 100g.

        Re-check the portion weights and the arithmetic, and answer again in the
        same format. If you cannot identify a food confidently, lower its
        confidence rather than guessing at numbers.
      TEXT
    end

    def record_usage(response)
      @provider = response.try(:model_id).presence || model
      @input_tokens = (@input_tokens || 0) + response.input_tokens.to_i
      @output_tokens = (@output_tokens || 0) + response.output_tokens.to_i
      @raw_response = response.content
    end

    def persist(extraction, latency_ms)
      unless extraction.valid?
        return failure(:invalid_extraction, extraction.failure_summary, latency_ms:)
      end

      ApplicationRecord.transaction do
        meal.items.destroy_all
        extraction.items.each { |item| create_item(item) }

        meal.update!(
          status: extraction.no_food? ? :not_food : :succeeded,
          model_id: model,
          provider: @provider,
          input_tokens: @input_tokens,
          output_tokens: @output_tokens,
          latency_ms: latency_ms,
          raw_response: @raw_response,
          analyzed_at: Time.current,
          failure_kind: nil,
          failure_reason: nil
        )
      end

      Result.new(status: meal.status, extraction:)
    end

    def create_item(item)
      meal.items.create!(
        food_name: item.name,
        grams: item.grams,
        confidence: item.confidence,
        kcal: item.kcal,
        protein_g: item.protein_g,
        carbs_g: item.carbs_g,
        fat_g: item.fat_g,
        **item.to_per_100g
      )
    end

    def failure(kind, reason, latency_ms: nil)
      meal.update!(
        status: :failed,
        failure_kind: kind,
        failure_reason: reason.to_s.truncate(1_000),
        model_id: model,
        input_tokens: @input_tokens,
        output_tokens: @output_tokens,
        latency_ms: latency_ms,
        # Kept on failure too, so a bad extraction can be inspected without
        # paying for the call a second time.
        raw_response: @raw_response
      )

      Result.new(status: :failed, failure_kind: kind, failure_reason: reason)
    end
  end
end
