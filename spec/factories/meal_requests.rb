FactoryBot.define do
  factory :meal_request do
    user
    meal
    reused { false }
  end
end
