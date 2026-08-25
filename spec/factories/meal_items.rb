FactoryBot.define do
  # Defaults describe a medium apple: ~52 kcal/100g, and the macros add up
  # under Atwater, so the factory never produces an implausible row.
  factory :meal_item do
    meal
    food_name { "Apple" }
    grams { 182 }
    confidence { 0.9 }

    kcal { 95 }
    protein_g { 0.5 }
    carbs_g { 25.1 }
    fat_g { 0.3 }

    kcal_per_100g { 52 }
    protein_per_100g { 0.3 }
    carbs_per_100g { 13.8 }
    fat_per_100g { 0.2 }
  end
end
