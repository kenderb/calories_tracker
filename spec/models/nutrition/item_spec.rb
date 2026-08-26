require "rails_helper"

RSpec.describe Nutrition::Item do
  # A medium apple. Real figures, and they add up under Atwater.
  def apple(**overrides)
    described_class.new(
      { name: "Apple", grams: 182, kcal: 95,
        protein_g: 0.5, carbs_g: 25.1, fat_g: 0.3, confidence: 0.9 }.merge(overrides)
    )
  end

  it "accepts a plausible food" do
    expect(apple).to be_valid
  end

  describe "basic bounds" do
    it "rejects a missing name" do
      expect(apple(name: nil)).not_to be_valid
    end

    it "rejects zero or negative weight" do
      expect(apple(grams: 0)).not_to be_valid
      expect(apple(grams: -10)).not_to be_valid
    end

    it "rejects an absurd weight" do
      expect(apple(grams: 50_000)).not_to be_valid
    end

    it "rejects negative macros" do
      expect(apple(protein_g: -2)).not_to be_valid
    end

    it "rejects confidence outside 0..1" do
      expect(apple(confidence: 1.2)).not_to be_valid
      expect(apple(confidence: -0.1)).not_to be_valid
    end

    it "allows a missing confidence" do
      expect(apple(confidence: nil)).to be_valid
    end
  end

  describe "energy cross-check" do
    # The point of this project: the schema cannot catch any of these, because
    # every one of them is a well-formed response.
    it "rejects calories that do not follow from the macros" do
      # 1g each of protein/carb/fat is 17 kcal, not 2000.
      item = apple(kcal: 2000, protein_g: 1, carbs_g: 1, fat_g: 1)

      expect(item).not_to be_valid
      expect(item.errors[:kcal].join).to include('does not match its macros')
    end

    it "rejects macros that do not follow from the calories" do
      # 50g of fat is 450 kcal on its own; 95 kcal is impossible.
      expect(apple(kcal: 95, protein_g: 0, carbs_g: 0, fat_g: 50)).not_to be_valid
    end

    it "reports how far apart the two figures are" do
      item = apple(kcal: 500, protein_g: 0.5, carbs_g: 25.1, fat_g: 0.3)
      item.valid?

      expect(item.errors[:kcal].join).to include("105.1 kcal by Atwater factors")
    end

    it "tolerates the drift that fibre and rounding actually cause" do
      # 102.5 kcal implied vs 95 stated: ~7% apart, which is normal.
      expect(apple).to be_valid
    end

    it "accepts drift right at the tolerance boundary" do
      # 100 kcal implied (25g carb), stated 125 -- exactly 25% of the larger.
      expect(apple(kcal: 125, protein_g: 0, carbs_g: 25, fat_g: 0)).to be_valid
    end

    it "still checks small portions, where a mismatch is just as wrong" do
      # 4g claiming 25 kcal from 1g of fat (9 kcal implied) is inconsistent
      # regardless of how little food it is.
      expect(apple(grams: 4, kcal: 25, protein_g: 0, carbs_g: 0, fat_g: 1)).not_to be_valid
    end

    it "skips the check for near-zero-calorie foods" do
      # Black coffee: nothing meaningful to divide by.
      expect(apple(name: "Black coffee", grams: 240, kcal: 2,
                   protein_g: 0.3, carbs_g: 0, fat_g: 0)).to be_valid
    end
  end

  describe "energy density" do
    it "rejects a food denser than pure fat" do
      # 200 kcal in 10g is 2000 kcal/100g -- above the 900 ceiling.
      item = apple(grams: 10, kcal: 200, protein_g: 0, carbs_g: 0, fat_g: 22.2)

      expect(item).not_to be_valid
      expect(item.errors[:kcal].join).to include('above the 900')
    end

    it "accepts olive oil, which sits just under the ceiling" do
      expect(apple(name: "Olive oil", grams: 14, kcal: 119,
                   protein_g: 0, carbs_g: 0, fat_g: 13.5)).to be_valid
    end
  end

  describe "#to_per_100g" do
    it "normalises nutrition to the reusable basis" do
      expect(apple.to_per_100g).to eq(
        kcal_per_100g: BigDecimal("52.2"),
        protein_per_100g: BigDecimal("0.27"),
        carbs_per_100g: BigDecimal("13.79"),
        fat_per_100g: BigDecimal("0.16")
      )
    end

    it "returns nils rather than dividing by zero" do
      expect(apple(grams: 0).to_per_100g.values).to all(be_nil)
    end
  end
end
