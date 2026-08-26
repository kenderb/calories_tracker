FactoryBot.define do
  factory :meal do
    sequence(:image_checksum) { |n| Digest::SHA256.hexdigest("photo-#{n}") }
    status { "pending" }

    trait :with_photo do
      after(:build) do |meal|
        meal.photo.attach(
          io: Rails.root.join("spec/fixtures/files/meal.jpg").open,
          filename: "meal.jpg",
          content_type: "image/jpeg"
        )
      end
    end

    trait :succeeded do
      status { "succeeded" }
      provider { "gemini" }
      model_id { "gemini-3.6-flash" }
      analyzed_at { Time.current }

      after(:create) do |meal|
        create(:meal_item, meal:)
      end
    end

    trait :not_food do
      status { "not_food" }
      analyzed_at { Time.current }
    end

    trait :failed do
      status { "failed" }
      failure_kind { "provider_error" }
      failure_reason { "upstream timed out" }
    end
  end
end
