require "vcr"
require "webmock/rspec"

VCR.configure do |config|
  config.cassette_library_dir = Rails.root.join("spec/cassettes").to_s
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Never let a real key reach a committed cassette.
  config.filter_sensitive_data("<GEMINI_API_KEY>") { ENV.fetch("GEMINI_API_KEY", nil).presence }
  config.filter_sensitive_data("<OPENAI_API_KEY>") { ENV.fetch("OPENAI_API_KEY", nil).presence }
  config.filter_sensitive_data("<AUTHORIZATION>") do |interaction|
    interaction.request.headers["Authorization"]&.first
  end
  # Gemini passes the key as a query parameter rather than a header.
  config.filter_sensitive_data("<GEMINI_API_KEY>") do |interaction|
    interaction.request.uri[/key=([^&]+)/, 1]
  end

  # Locally, record a cassette the first time a spec needs one.
  # In CI, RECORD_MODE=none — an unmatched request fails the spec loudly
  # instead of silently reaching out to a provider and spending tokens.
  config.default_cassette_options = {
    record: ENV.fetch("VCR_RECORD_MODE", "once").to_sym,
    match_requests_on: [ :method, :uri, :body ]
  }

  config.ignore_localhost = true
end
