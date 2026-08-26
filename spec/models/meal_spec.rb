require "rails_helper"

RSpec.describe Meal do
  it { is_expected.to have_many(:items).dependent(:destroy) }
  it { is_expected.to validate_presence_of(:image_checksum) }

  it "refuses a second meal with the same image checksum" do
    checksum = Digest::SHA256.hexdigest("same-photo")
    create(:meal, image_checksum: checksum)

    expect { create(:meal, image_checksum: checksum) }
      .to raise_error(ActiveRecord::RecordInvalid)
  end

  it "enforces uniqueness at the database level too" do
    # The unique index is what actually prevents two concurrent uploads of the
    # same photo from both spending a model call; the validation alone races.
    checksum = Digest::SHA256.hexdigest("racy-photo")
    create(:meal, image_checksum: checksum)

    duplicate = build(:meal, image_checksum: checksum)

    expect { duplicate.save(validate: false) }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  describe "#settled?" do
    it "is false while pending" do
      expect(build(:meal, status: "pending")).not_to be_settled
    end

    it "is false while processing" do
      expect(build(:meal, status: "processing")).not_to be_settled
    end

    it "is true once succeeded, failed, or judged not food" do
      %w[succeeded failed not_food].each do |status|
        expect(build(:meal, status:)).to be_settled
      end
    end
  end

  describe "#original_request" do
    it "is the upload that created the analysis, not a later reuse" do
      meal = create(:meal, :succeeded)
      uploader = create(:user)
      create(:meal_request, meal:, user: uploader)
      create(:meal_request, meal:, user: create(:user), reused: true)

      expect(meal.reload.original_request.user).to eq(uploader)
    end

    it "stays the same however many people re-upload the photo" do
      meal = create(:meal, :succeeded)
      uploader = create(:user)
      create(:meal_request, meal:, user: uploader)
      3.times { create(:meal_request, meal:, user: create(:user), reused: true) }

      expect(meal.reload.original_request.user).to eq(uploader)
    end

    it "is nil for a meal nobody has requested" do
      expect(create(:meal).original_request).to be_nil
    end
  end

  describe ".reusable" do
    it "includes settled analyses worth serving from cache" do
      succeeded = create(:meal, :succeeded)
      not_food = create(:meal, :not_food)
      create(:meal, :failed)
      create(:meal, status: "pending")

      expect(described_class.reusable).to contain_exactly(succeeded, not_food)
    end
  end

  it "sums calories across its items" do
    meal = create(:meal, :succeeded)
    create(:meal_item, meal:, kcal: 105)

    expect(meal.reload.total_kcal).to eq(200)
  end

  it "accepts a photo attachment" do
    meal = create(:meal, :with_photo)

    expect(meal.photo).to be_attached
  end
end
