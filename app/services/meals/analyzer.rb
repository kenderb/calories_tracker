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

    # Retryable: the request may well succeed on another attempt, so these
    # propagate out of #call for AnalyzeMealJob's retry policy to act on.
    class ProviderError < StandardError; end
    class RateLimited < ProviderError; end

    # Terminal: another attempt would fail the same way. These are recorded on
    # the meal and swallowed, because there is nothing for the job to retry.
    class ContentFiltered < StandardError; end
    class ConfigurationError < StandardError; end

    # ruby_llm splits its errors across two families: HTTP failures subclass
    # RubyLLM::Error, while setup failures (missing key, unknown model) subclass
    # StandardError directly. Rescuing only RubyLLM::Error misses the second
    # family entirely and leaves the meal stuck in `processing`, so both are
    # mapped explicitly below.
    SETUP_ERRORS = [
      RubyLLM::ConfigurationError,   # no API key for the chosen provider
      RubyLLM::ModelNotFoundError,   # model id absent from the bundled registry
      RubyLLM::InvalidRoleError,
      RubyLLM::InvalidToolChoiceError,
      RubyLLM::UnsupportedAttachmentError
    ].freeze

    # HTTP failures a human has to fix: credentials, billing, permissions.
    ACCESS_ERRORS = [
      RubyLLM::UnauthorizedError,
      RubyLLM::PaymentRequiredError,
      RubyLLM::ForbiddenError
    ].freeze

    # HTTP failures that are worth another attempt.
    TRANSIENT_ERRORS = [
      RubyLLM::ServerError,
      RubyLLM::ServiceUnavailableError,
      RubyLLM::OverloadedError,
      Faraday::TimeoutError,
      Faraday::ConnectionFailed,
      Net::ReadTimeout
    ].freeze

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
    rescue RateLimited, ProviderError
      # Leave the meal claimable by the retry rather than marking it failed --
      # `failed` counts as settled, and the job skips settled meals.
      meal.update!(status: :pending)
      raise
    rescue ContentFiltered => e
      failure(:content_filtered, e.message)
    rescue ConfigurationError => e
      failure(:configuration_error, e.message)
    rescue StandardError => e
      # Nothing should reach here, but a meal must never be left in
      # `processing`. Record it, then re-raise so the failure is still visible
      # in the job's failed executions rather than silently absorbed.
      failure(:provider_error, "#{e.class}: #{e.message}")
      raise
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
      build_chat
        .with_instructions(Prompt::SYSTEM)
        .with_schema(NutritionSchema)
    rescue *SETUP_ERRORS => e
      # Raised before any request is made -- an unknown model id, or no API key
      # for the chosen provider. An unknown model usually means it is newer than
      # the installed gem; set LLM_PROVIDER to skip the registry check.
      raise ConfigurationError, e.message
    end

    def build_chat
      if LlmConfig.skip_registry_check?
        RubyLLM.chat(model: model, provider: LlmConfig.provider, assume_model_exists: true)
      else
        RubyLLM.chat(model: model)
      end
    end

    # Translates both of ruby_llm's error families into the retry taxonomy.
    def ask(_chat)
      yield
    rescue RubyLLM::RateLimitError => e
      raise RateLimited, e.message
    rescue *ACCESS_ERRORS => e
      raise ConfigurationError, e.message
    rescue *SETUP_ERRORS => e
      raise ConfigurationError, e.message
    rescue *TRANSIENT_ERRORS => e
      raise ProviderError, "#{e.class}: #{e.message}"
    rescue RubyLLM::BadRequestError, RubyLLM::ContextLengthExceededError => e
      # Malformed or oversized request: the same call would fail again.
      raise ContentFiltered, e.message
    rescue RubyLLM::Error => e
      raise ProviderError, e.message
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
