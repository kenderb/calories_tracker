# One food detected in a photo.
#
# Macros are stored twice: as reported for this item's `grams`, and normalised
# to 100g. The per-100g figures are the reusable part -- they let a later
# service answer "what about 90g?" arithmetically instead of asking a model.
class MealItem < ApplicationRecord
  belongs_to :meal

  before_validation :normalize_name

  validates :food_name, presence: true
  validates :grams, numericality: { greater_than: 0 }
  validates :kcal, :protein_g, :carbs_g, :fat_g,
            :kcal_per_100g, :protein_per_100g, :carbs_per_100g, :fat_per_100g,
            numericality: { greater_than_or_equal_to: 0 }
  validates :confidence,
            numericality: { in: 0..1 },
            allow_nil: true

  # Scale this food's nutrition to an arbitrary weight, from the stored per-100g
  # basis. No model call involved.
  def at_grams(target_grams)
    factor = target_grams.to_d / 100
    {
      grams: target_grams.to_d,
      kcal: (kcal_per_100g * factor).round(2),
      protein_g: (protein_per_100g * factor).round(2),
      carbs_g: (carbs_per_100g * factor).round(2),
      fat_g: (fat_per_100g * factor).round(2)
    }
  end

  private

  def normalize_name
    self.normalized_name = food_name.to_s.strip.downcase.squeeze(" ")
  end
end
