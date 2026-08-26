require "rails_helper"

RSpec.describe Nutrition::Extraction do
  def valid_item(**overrides)
    { "name" => "Apple", "grams" => 182, "kcal" => 95,
      "protein_g" => 0.5, "carbs_g" => 25.1, "fat_g" => 0.3,
      "confidence" => 0.9 }.merge(overrides.stringify_keys)
  end

  describe ".from_payload" do
    it "builds from the string-keyed hash a provider returns" do
      extraction = described_class.from_payload(
        "food_detected" => true,
        "items" => [ valid_item ],
        "notes" => "Scale estimated from the plate."
      )

      expect(extraction).to be_valid
      expect(extraction.items.size).to eq(1)
      expect(extraction.items.first.name).to eq("Apple")
      expect(extraction.notes).to eq("Scale estimated from the plate.")
    end

    it "survives a nil payload rather than raising" do
      extraction = described_class.from_payload(nil)

      expect(extraction.items).to be_empty
      expect(extraction).to be_no_food
    end

    it "survives a payload missing the items key" do
      expect(described_class.from_payload("food_detected" => false).items).to be_empty
    end
  end

  describe "consistency between food_detected and items" do
    it "rejects a claim of food with nothing itemised" do
      extraction = described_class.from_payload("food_detected" => true, "items" => [])

      expect(extraction).not_to be_valid
      expect(extraction.failure_summary).to include('must not be empty')
    end

    it "rejects items alongside a claim of no food" do
      extraction = described_class.from_payload("food_detected" => false, "items" => [ valid_item ])

      expect(extraction).not_to be_valid
      expect(extraction.failure_summary).to include('must be empty')
    end

    it "accepts an honest 'this is not food'" do
      extraction = described_class.from_payload(
        "food_detected" => false, "items" => [], "notes" => "This is a bicycle."
      )

      expect(extraction).to be_valid
      expect(extraction).to be_no_food
    end
  end

  describe "propagating item-level problems" do
    it "is invalid when any single item is implausible" do
      extraction = described_class.from_payload(
        "food_detected" => true,
        "items" => [ valid_item, valid_item(name: "Lettuce", grams: 1, kcal: 2000) ]
      )

      expect(extraction).not_to be_valid
    end

    it "names the offending food in the failure summary" do
      extraction = described_class.from_payload(
        "food_detected" => true,
        "items" => [ valid_item, valid_item(name: "Lettuce", grams: 1, kcal: 2000) ]
      )
      extraction.valid?

      # The summary is fed back to the model as a repair turn, so it has to say
      # which food was wrong, not just that something was.
      expect(extraction.failure_summary).to include("Lettuce")
      expect(extraction.failure_summary).not_to include("Apple:")
    end
  end

  it "sums calories across items" do
    extraction = described_class.from_payload(
      "food_detected" => true,
      "items" => [ valid_item, valid_item(name: "Banana", kcal: 105, carbs_g: 27, protein_g: 1.3, fat_g: 0.4) ]
    )

    expect(extraction.total_kcal).to eq(200)
  end
end
