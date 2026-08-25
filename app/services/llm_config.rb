# Single place that decides which model runs the vision extraction.
#
# ruby_llm infers the provider from the model id, so switching from Gemini to
# OpenAI (or anything else it supports) is an env change, not a code change.
module LlmConfig
  DEFAULT_MODEL = "gemini-3.6-flash".freeze
  DEFAULT_TIMEOUT = 60

  module_function

  def model
    ENV.fetch("LLM_MODEL", DEFAULT_MODEL)
  end

  def timeout
    Integer(ENV.fetch("LLM_TIMEOUT", DEFAULT_TIMEOUT))
  end

  # Which provider key is actually populated. Used by the health check and to
  # fail fast at boot rather than at the first upload.
  def configured?
    ENV["GEMINI_API_KEY"].present? || ENV["OPENAI_API_KEY"].present?
  end
end
