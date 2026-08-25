FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.test" }
    name { "Test User" }
  end
end
