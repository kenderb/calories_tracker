# Single place that decides which model runs the vision extraction.
#
# ruby_llm ships a bundled registry of known models and rejects ids it does not
# recognise. That registry is only as current as the gem release, and model ids
# move faster than gem releases -- so setting LLM_PROVIDER explicitly skips the
# registry check and lets a newer id work immediately.
module LlmConfig
  DEFAULT_MODEL = "gemini-3.5-flash".freeze
  DEFAULT_TIMEOUT = 60

  module_function

  def model
    ENV.fetch("LLM_MODEL", DEFAULT_MODEL)
  end

  # Set this to use a model newer than the installed ruby_llm knows about.
  # Without it, the id is validated against the bundled registry first, which
  # catches typos before they cost a request.
  def provider
    ENV["LLM_PROVIDER"].presence&.to_sym
  end

  # Skipping registry validation requires naming the provider, since ruby_llm
  # can no longer infer it from a model id it does not recognise.
  def skip_registry_check?
    provider.present?
  end

  def timeout
    Integer(ENV.fetch("LLM_TIMEOUT", DEFAULT_TIMEOUT))
  end

  def configured?
    ENV["GEMINI_API_KEY"].present? || ENV["OPENAI_API_KEY"].present?
  end
end
