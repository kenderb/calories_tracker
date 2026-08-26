require "rails_helper"

RSpec.describe User do
  it { is_expected.to have_many(:meal_requests).dependent(:destroy) }
  it { is_expected.to have_many(:meals).through(:meal_requests) }

  it { is_expected.to validate_presence_of(:email) }

  it "rejects a malformed email" do
    expect(build(:user, email: "not-an-email")).not_to be_valid
  end

  it "downcases and strips the email before saving" do
    user = create(:user, email: "  MixedCase@Example.TEST ")

    expect(user.email).to eq("mixedcase@example.test")
  end

  it "rejects a duplicate email regardless of case" do
    create(:user, email: "taken@example.test")

    expect(build(:user, email: "TAKEN@example.test")).not_to be_valid
  end

  it "generates an api token on create" do
    expect(create(:user).api_token).to be_present
  end

  it "gives each user a distinct token" do
    expect(create(:user).api_token).not_to eq(create(:user).api_token)
  end
end
