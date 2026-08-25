require "rails_helper"

RSpec.configure do |config|
  config.openapi_root = Rails.root.join("swagger").to_s

  config.openapi_specs = {
    "v1/swagger.yaml" => {
      openapi: "3.0.3",
      info: {
        title: "Calories Tracker API",
        version: "v1",
        description: <<~DESC
          Turns a photo of a meal into structured, validated nutrition data.

          Analysis is asynchronous. POST a photo and you get `202 Accepted` with
          an id; poll GET until `status` leaves `pending`/`processing`.

          Photos are content-addressed by the SHA-256 of their bytes, and the
          resulting analysis is global rather than per-user. Uploading a photo
          that has already been analysed -- by you or anyone else -- returns
          `200 OK` with `reused: true` and the stored result, and costs nothing.
        DESC
      },
      paths: {},
      servers: [
        { url: "http://localhost:3000", description: "Local development" }
      ],
      components: {
        securitySchemes: {
          bearer_auth: {
            type: :http,
            scheme: :bearer,
            description: "Your API token, sent as `Authorization: Bearer <token>`."
          }
        },
        schemas: {
          Macros: {
            type: :object,
            properties: {
              kcal: { type: :number, format: :float },
              protein_g: { type: :number, format: :float },
              carbs_g: { type: :number, format: :float },
              fat_g: { type: :number, format: :float }
            },
            required: %w[kcal protein_g carbs_g fat_g]
          },
          MealItem: {
            type: :object,
            properties: {
              food_name: { type: :string, example: "Apple" },
              grams: { type: :number, format: :float, example: 182.0 },
              confidence: {
                type: :number, format: :float, nullable: true, example: 0.92,
                description: "The model's confidence in this item, 0.0 to 1.0."
              },
              kcal: { type: :number, format: :float },
              protein_g: { type: :number, format: :float },
              carbs_g: { type: :number, format: :float },
              fat_g: { type: :number, format: :float },
              per_100g: {
                allOf: [ { "$ref" => "#/components/schemas/Macros" } ],
                description: "Nutrition normalised to 100g. Use this to re-weigh " \
                             "the food client-side instead of making another request."
              }
            },
            required: %w[food_name grams kcal protein_g carbs_g fat_g per_100g]
          },
          Meal: {
            type: :object,
            properties: {
              id: { type: :integer },
              status: {
                type: :string,
                enum: %w[pending processing succeeded not_food failed],
                description: "`not_food` means the model looked and found no food. " \
                             "That is an answer, not an error."
              },
              reused: {
                type: :boolean,
                description: "True when this response came from an existing analysis."
              },
              created_at: { type: :string, format: :"date-time" },
              analyzed_at: { type: :string, format: :"date-time", nullable: true },
              items: { type: :array, items: { "$ref" => "#/components/schemas/MealItem" } },
              total: { "$ref" => "#/components/schemas/Macros" },
              model: {
                type: :object,
                properties: {
                  id: { type: :string, example: "gemini-3.6-flash" },
                  latency_ms: { type: :integer, nullable: true }
                }
              },
              failure: {
                type: :object,
                description: "Present only when status is `failed`.",
                properties: {
                  kind: {
                    type: :string,
                    enum: %w[provider_error rate_limited invalid_extraction content_filtered],
                    description: "`invalid_extraction` means the model returned " \
                                 "well-formed but nutritionally impossible figures."
                  },
                  reason: { type: :string }
                }
              }
            },
            required: %w[id status reused created_at]
          },
          Problem: {
            type: :object,
            description: "RFC 9457 problem details. Every error uses this shape.",
            properties: {
              title: { type: :string },
              detail: { type: :string },
              status: { type: :integer }
            },
            required: %w[title detail status]
          }
        }
      },
      security: [ { bearer_auth: [] } ]
    }
  }

  config.openapi_format = :yaml
end
