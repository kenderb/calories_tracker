require "rails_helper"

RSpec.describe MealItem do
  it { is_expected.to belong_to(:meal) }

  it "rejects zero or negative weight" do
    expect(build(:meal_item, grams: 0)).not_to be_valid
    expect(build(:meal_item, grams: -5)).not_to be_valid
  end

  it "rejects negative macros" do
    expect(build(:meal_item, protein_g: -1)).not_to be_valid
  end

  it "rejects a confidence outside 0..1" do
    expect(build(:meal_item, confidence: 1.5)).not_to be_valid
  end

  it "allows a missing confidence" do
    expect(build(:meal_item, confidence: nil)).to be_valid
  end

  it "normalizes the food name for lookup" do
    item = create(:meal_item, food_name: "  Granny   Smith Apple ")

    expect(item.normalized_name).to eq("granny smith apple")
  end

  describe "#at_grams" do
    # This is the whole point of storing a per-100g basis: re-weighing a known
    # food is arithmetic, not another model call.
    subject(:item) do
      build(:meal_item,
            kcal_per_100g: 52, protein_per_100g: 0.3,
            carbs_per_100g: 13.8, fat_per_100g: 0.2)
    end

    it "scales nutrition to an arbitrary weight" do
      expect(item.at_grams(90)).to eq(
        grams: BigDecimal("90"),
        kcal: BigDecimal("46.8"),
        protein_g: BigDecimal("0.27"),
        carbs_g: BigDecimal("12.42"),
        fat_g: BigDecimal("0.18")
      )
    end

    it "returns the per-100g basis unchanged at 100g" do
      expect(item.at_grams(100)).to include(kcal: BigDecimal("52"))
    end
  end
end
