Rswag::Ui.configure do |c|
  # Swagger UI at /api-docs, reading the document the API engine serves.
  c.openapi_endpoint "/api-docs/v1/swagger.yaml", "Calories Tracker API V1"
end
