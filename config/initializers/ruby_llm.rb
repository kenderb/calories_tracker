RubyLLM.configure do |config|
  # Only the key for the provider you actually use needs to be set; ruby_llm
  # raises RubyLLM::ConfigurationError if you reach for an unconfigured one.
  config.gemini_api_key = ENV.fetch("GEMINI_API_KEY", nil)
  config.openai_api_key = ENV.fetch("OPENAI_API_KEY", nil)

  # A vision call is slow but not unbounded. The job layer owns retries, so a
  # hung request should fail fast enough to be retried rather than tie up a
  # worker thread.
  config.request_timeout = Integer(ENV.fetch("LLM_TIMEOUT", 60))
  config.max_retries = 0

  # Opt in to the current ActiveRecord integration. We do not use acts_as_chat,
  # but this flag also silences the 2.0 deprecation banner on every boot.
  config.use_new_acts_as = true
end

# NOTE: the model is deliberately not set as a global default here. Initializers
# run before autoloading, so LlmConfig is not available yet -- and passing the
# model explicitly at the call site keeps it obvious which model ran a given
# extraction.
