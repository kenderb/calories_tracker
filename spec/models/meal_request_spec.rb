require "rails_helper"

RSpec.describe MealRequest do
  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:meal) }

  it "lets one meal serve many users, which is the point of not scoping it" do
    meal = create(:meal, :succeeded)
    create(:meal_request, meal:, user: create(:user))
    create(:meal_request, meal:, user: create(:user), reused: true)

    expect(meal.meal_requests.count).to eq(2)
    expect(described_class.reused.count).to eq(1)
  end
end
