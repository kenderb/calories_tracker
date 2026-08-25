require "swagger_helper"

# These specs are the OpenAPI source. `rake rswag:specs:swaggerize` runs them
# and writes swagger/v1/swagger.yaml from what actually happened, and CI fails
# if the committed document differs -- so the docs cannot drift from the code.
RSpec.describe "Api::V1::Meals" do
  let(:user) { create(:user) }
  let(:Authorization) { "Bearer #{user.api_token}" }
  let(:photo) { fixture_file_upload("meal.jpg", "image/jpeg") }
  let(:fixture_checksum) do
    Digest::SHA256.hexdigest(Rails.root.join("spec/fixtures/files/meal.jpg").read)
  end

  path "/api/v1/meals" do
    post "Analyze a meal photo" do
      tags "Meals"
      consumes "multipart/form-data"
      produces "application/json"
      description <<~DESC
        Uploads a photo for analysis.

        Returns `202 Accepted` when a new analysis was queued -- poll the URL in
        the `Location` header until `status` leaves `pending`/`processing`.

        Returns `200 OK` when this exact image has already been analysed. The
        stored result comes back immediately with `reused: true`, and no model
        call is made.
      DESC
      security [ { bearer_auth: [] } ]

      # rswag copies this schema straight into the OpenAPI requestBody, and
      # separately builds the test request keyed by the parameter name. So the
      # schema describes the whole multipart body (which is what Swagger UI
      # needs to render a file picker), while `name:` still drives the request.
      parameter name: :photo, in: :formData, required: true,
                schema: {
                  type: :object,
                  properties: {
                    photo: {
                      type: :string,
                      format: :binary,
                      description: "JPEG, PNG, WebP or HEIC, up to 10MB."
                    }
                  },
                  required: [ "photo" ]
                }

      response "202", "analysis queued" do
        schema "$ref" => "#/components/schemas/Meal"
        header "Location", schema: { type: :string }, description: "Where to poll for the result."

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["status"]).to eq("pending")
          expect(body["reused"]).to be(false)
          expect(response.headers["Location"]).to end_with("/api/v1/meals/#{body['id']}")
        end
      end

      response "200", "this photo was already analysed; stored result returned" do
        schema "$ref" => "#/components/schemas/Meal"

        before { create(:meal, :succeeded, image_checksum: fixture_checksum) }

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["reused"]).to be(true)
          expect(body["status"]).to eq("succeeded")
        end
      end

      response "400", "no photo supplied" do
        schema "$ref" => "#/components/schemas/Problem"
        let(:photo) { nil }

        run_test!
      end

      response "401", "missing or invalid token" do
        schema "$ref" => "#/components/schemas/Problem"
        let(:Authorization) { "Bearer not-a-real-token" }

        run_test!
      end

      response "415", "file is not a supported image type" do
        schema "$ref" => "#/components/schemas/Problem"
        let(:photo) { fixture_file_upload("meal.jpg", "application/pdf") }

        run_test!
      end
    end
  end

  path "/api/v1/meals/{id}" do
    parameter name: :id, in: :path, type: :integer, description: "Meal id."

    get "Fetch a meal analysis" do
      tags "Meals"
      produces "application/json"
      description <<~DESC
        Returns the current state of an analysis.

        While `status` is `pending` or `processing` the nutrition fields are
        absent. Once `succeeded`, `items` and `total` are populated, and each
        item carries a `per_100g` basis for re-weighing client-side.

        Meals are global, so any authenticated user may read any meal id.
      DESC
      security [ { bearer_auth: [] } ]

      response "200", "analysis complete" do
        schema "$ref" => "#/components/schemas/Meal"
        let(:id) { create(:meal, :succeeded).id }

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["status"]).to eq("succeeded")
          expect(body["items"].first).to include("food_name" => "Apple", "grams" => 182.0)
          expect(body["total"]["kcal"]).to eq(95.0)
          expect(body["items"].first["per_100g"]).to include("kcal" => 52.0)
        end
      end

      response "200", "analysis still running" do
        schema "$ref" => "#/components/schemas/Meal"
        let(:id) { create(:meal).id }

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["status"]).to eq("pending")
          expect(body).not_to have_key("items")
        end
      end

      response "404", "no meal with that id" do
        schema "$ref" => "#/components/schemas/Problem"
        let(:id) { 999_999 }

        run_test!
      end

      response "401", "missing or invalid token" do
        schema "$ref" => "#/components/schemas/Problem"
        let(:id) { create(:meal).id }
        let(:Authorization) { "" }

        run_test!
      end
    end
  end
end
