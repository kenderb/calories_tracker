require "rails_helper"

# Behaviour that matters but is not a distinct entry in the HTTP contract --
# several of these are all 200 responses, so documenting them separately in
# OpenAPI would add noise. The contract itself lives in meals_spec.rb.
RSpec.describe "Api::V1::Meals behaviour" do
  let(:user) { create(:user) }
  let(:headers) { { "Authorization" => "Bearer #{user.api_token}" } }
  let(:photo) { fixture_file_upload("meal.jpg", "image/jpeg") }
  let(:checksum) { Digest::SHA256.hexdigest(Rails.root.join("spec/fixtures/files/meal.jpg").read) }

  def body = response.parsed_body

  describe "authentication" do
    it "rejects a request with no Authorization header at all" do
      post "/api/v1/meals", params: { photo: photo }

      expect(response).to have_http_status(:unauthorized)
      expect(response.media_type).to eq("application/problem+json")
    end

    it "rejects a bare token sent without the Bearer scheme" do
      post "/api/v1/meals", params: { photo: photo },
           headers: { "Authorization" => user.api_token }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "reuse" do
    it "spends no model call on a photo already analysed" do
      create(:meal, :succeeded, image_checksum: checksum)

      expect { post "/api/v1/meals", params: { photo: photo }, headers: headers }
        .not_to have_enqueued_job(AnalyzeMealJob)
    end

    it "reuses across users, not just within one" do
      create(:meal, :succeeded, image_checksum: checksum)
      stranger = create(:user)

      post "/api/v1/meals", params: { photo: photo },
           headers: { "Authorization" => "Bearer #{stranger.api_token}" }

      expect(body["reused"]).to be(true)
    end

    it "records each request even when the analysis is reused" do
      create(:meal, :succeeded, image_checksum: checksum)

      expect { post "/api/v1/meals", params: { photo: photo }, headers: headers }
        .to change(MealRequest, :count).by(1)
    end
  end

  describe "non-success outcomes" do
    it "reports a photo with no food as an empty result rather than an error" do
      meal = create(:meal, :not_food)

      get "/api/v1/meals/#{meal.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(body["status"]).to eq("not_food")
      expect(body["items"]).to eq([])
      expect(body["total"]["kcal"]).to eq(0.0)
    end

    it "explains a failure without exposing the raw provider payload" do
      meal = create(:meal, :failed)

      get "/api/v1/meals/#{meal.id}", headers: headers

      expect(body["failure"]).to eq("kind" => "provider_error", "reason" => "upstream timed out")
      expect(body).not_to have_key("raw_response")
    end
  end

  it "lets any authenticated user read any meal, since meals are global" do
    meal = create(:meal, :succeeded)
    stranger = create(:user)

    get "/api/v1/meals/#{meal.id}",
        headers: { "Authorization" => "Bearer #{stranger.api_token}" }

    expect(response).to have_http_status(:ok)
  end

  # The 400/415 contract is documented in meals_spec.rb; these are the
  # rejections that would only add noise to the OpenAPI document.
  describe "rejected uploads" do
    it "refuses a photo bigger than the limit" do
      stub_const("Meals::PhotoValidator::MAX_BYTES", 10)

      post "/api/v1/meals", params: { photo: photo }, headers: headers

      expect(response).to have_http_status(:content_too_large)
      expect(response.media_type).to eq("application/problem+json")
    end

    it "refuses a `photo` that came through as a string rather than a file" do
      post "/api/v1/meals", params: { photo: "https://example.com/lunch.jpg" }, headers: headers

      expect(response).to have_http_status(:bad_request)
      expect(body["detail"]).to eq("`photo` must be an uploaded file.")
    end

    it "tells the client which type it actually sent" do
      post "/api/v1/meals", params: { photo: fixture_file_upload("meal.jpg", "application/pdf") },
           headers: headers

      expect(body["received"]).to eq("application/pdf")
    end

    it "stores nothing when the upload is refused" do
      expect do
        post "/api/v1/meals", params: { photo: fixture_file_upload("meal.jpg", "application/pdf") },
             headers: headers
      end.not_to change(Meal, :count)
    end
  end
end
