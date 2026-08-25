require "rails_helper"

RSpec.describe Meals::Intake do
  subject(:intake) { described_class.new(user:, upload:) }

  let(:user) { create(:user) }
  let(:upload) { fixture_file_upload("meal.jpg", "image/jpeg") }

  def another_upload
    fixture_file_upload("meal.jpg", "image/jpeg")
  end

  describe "a photo never seen before" do
    it "creates a pending meal" do
      result = intake.call

      expect(result.meal).to be_pending
      expect(result).not_to be_reused
    end

    it "attaches the photo" do
      expect(intake.call.meal.photo).to be_attached
    end

    it "keys the meal by the checksum of the image bytes" do
      expected = Digest::SHA256.hexdigest(Rails.root.join("spec/fixtures/files/meal.jpg").read)

      expect(intake.call.meal.image_checksum).to eq(expected)
    end

    it "queues the analysis" do
      expect { intake.call }.to have_enqueued_job(AnalyzeMealJob)
    end

    it "records who asked" do
      result = intake.call

      expect(result.meal_request.user).to eq(user)
      expect(result.meal_request).not_to be_reused
    end
  end

  describe "a photo that has already been analysed" do
    before { create(:meal, :succeeded, image_checksum: Digest::SHA256.hexdigest(Rails.root.join("spec/fixtures/files/meal.jpg").read)) }

    it "serves the stored analysis" do
      expect(intake.call).to be_reused
    end

    it "does not queue another call" do
      # This is the whole point: the second upload of a photo costs nothing.
      expect { intake.call }.not_to have_enqueued_job(AnalyzeMealJob)
    end

    it "does not create a second meal" do
      expect { intake.call }.not_to change(Meal, :count)
    end

    it "still records that this user asked" do
      expect { intake.call }.to change(MealRequest, :count).by(1)
    end

    it "reuses across users, not just within one" do
      other = described_class.new(user: create(:user), upload: another_upload).call

      expect(other).to be_reused
    end
  end

  describe "a photo whose analysis is still in flight" do
    before { create(:meal, status: "pending", image_checksum: Digest::SHA256.hexdigest(Rails.root.join("spec/fixtures/files/meal.jpg").read)) }

    it "does not serve an unfinished analysis from cache" do
      # Only settled meals are reusable; a pending one has nothing to return.
      # The unique index then makes the duplicate insert fail, and the loser
      # joins the in-flight analysis rather than starting a second one.
      result = intake.call

      expect(result).to be_reused
      expect(Meal.count).to eq(1)
    end

    it "does not queue a duplicate call" do
      expect { intake.call }.not_to have_enqueued_job(AnalyzeMealJob)
    end
  end

  describe "a photo whose previous analysis failed" do
    before { create(:meal, :failed, image_checksum: Digest::SHA256.hexdigest(Rails.root.join("spec/fixtures/files/meal.jpg").read)) }

    it "is never served from cache -- a failure is not an answer" do
      expect(Meal.reusable).to be_empty
    end

    it "retries on the same record rather than creating a second one" do
      expect { intake.call }.not_to change(Meal, :count)
    end

    it "resets the meal to pending and clears the previous failure" do
      meal = intake.call.meal

      expect(meal).to be_pending
      expect(meal.failure_kind).to be_nil
      expect(meal.failure_reason).to be_nil
    end

    it "queues a fresh analysis" do
      expect { intake.call }.to have_enqueued_job(AnalyzeMealJob)
    end

    it "is not reported as reused, because it does cost a call" do
      expect(intake.call).not_to be_reused
    end
  end
end
