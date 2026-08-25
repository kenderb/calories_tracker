Rswag::Api.configure do |c|
  # Where the generated OpenAPI documents live. `rake rswag:specs:swaggerize`
  # writes here; the API engine serves them from /api-docs.
  c.openapi_root = Rails.root.join("swagger").to_s
end
