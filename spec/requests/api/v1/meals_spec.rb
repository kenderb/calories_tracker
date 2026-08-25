require "rails_helper"

RSpec.describe "Api::V1::Meals" do
  let(:user) { create(:user) }
  let(:headers) { { "Authorization" => "Bearer #{user.api_token}" } }
  let(:photo) { fixture_file_upload("meal.jpg", "image/jpeg") }
  let(:checksum) { Digest::SHA256.hexdigest(Rails.root.join("spec/fixtures/files/meal.jpg").read) }

  def body = response.parsed_body

  describe "authentication" do
    it "rejects a request with no token" do
      post "/api/v1/meals", params: { photo: }

      expect(response).to have_http_status(:unauthorized)
      expect(response.media_type).to eq("application/problem+json")
    end

    it "rejects an unknown token" do
      post "/api/v1/meals", params: { photo: }, headers: { "Authorization" => "Bearer nope" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a token sent without the Bearer scheme" do
      post "/api/v1/meals", params: { photo: }, headers: { "Authorization" => user.api_token }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/meals" do
    it "accepts the upload and queues the analysis" do
      post "/api/v1/meals", params: { photo: }, headers: headers
      expect(response).to have_http_status(:accepted)
      expect(body["status"]).to eq("pending")
      expect(body["reused"]).to be(false)
    end

    it "returns a Location header pointing at the result" do
      post "/api/v1/meals", params: { photo: }, headers: headers
      expect(response.headers["Location"]).to end_with("/api/v1/meals/#{body['id']}")
    end

    it "returns 200 and the stored analysis for a photo already seen" do
      create(:meal, :succeeded, image_checksum: checksum)

      post "/api/v1/meals", params: { photo: }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(body["reused"]).to be(true)
      expect(body["status"]).to eq("succeeded")
    end

    it "spends no model call on a photo already seen" do
      create(:meal, :succeeded, image_checksum: checksum)

      expect { post "/api/v1/meals", params: { photo: }, headers: }
        .not_to have_enqueued_job(AnalyzeMealJob)
    end

    it "requires a photo" do
      post "/api/v1/meals", params: {}, headers: headers
      expect(response).to have_http_status(:bad_request)
    end

    it "rejects a file that is not an image" do
      post "/api/v1/meals",
           params: { photo: fixture_file_upload("meal.jpg", "application/pdf") },
           headers: headers
      expect(response).to have_http_status(:unsupported_media_type)
    end
  end

  describe "GET /api/v1/meals/:id" do
    it "reports a pending analysis without nutrition data" do
      meal = create(:meal)

      get "/api/v1/meals/#{meal.id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(body["status"]).to eq("pending")
      expect(body).not_to have_key("items")
    end

    it "returns items and totals once succeeded" do
      meal = create(:meal, :succeeded)

      get "/api/v1/meals/#{meal.id}", headers: headers
      expect(body["status"]).to eq("succeeded")
      expect(body["items"].first).to include("food_name" => "Apple", "grams" => 182.0)
      expect(body["total"]["kcal"]).to eq(95.0)
    end

    it "exposes the per-100g basis so a client can re-weigh a food" do
      meal = create(:meal, :succeeded)

      get "/api/v1/meals/#{meal.id}", headers: headers
      expect(body["items"].first["per_100g"]).to include("kcal" => 52.0)
    end

    it "reports a photo with no food as an empty result, not an error" do
      meal = create(:meal, :not_food)

      get "/api/v1/meals/#{meal.id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(body["status"]).to eq("not_food")
      expect(body["items"]).to eq([])
    end

    it "explains a failure without leaking the raw payload" do
      meal = create(:meal, :failed)

      get "/api/v1/meals/#{meal.id}", headers: headers
      expect(body["failure"]).to eq("kind" => "provider_error", "reason" => "upstream timed out")
      expect(body).not_to have_key("raw_response")
    end

    it "returns problem+json for an unknown id" do
      get "/api/v1/meals/999999", headers: headers
      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("application/problem+json")
    end

    it "lets any authenticated user read a meal, since meals are global" do
      meal = create(:meal, :succeeded)
      other = create(:user)

      get "/api/v1/meals/#{meal.id}", headers: { "Authorization" => "Bearer #{other.api_token}" }

      expect(response).to have_http_status(:ok)
    end
  end
end
