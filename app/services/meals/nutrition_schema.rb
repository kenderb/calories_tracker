module Meals
  # Layer one of two. This constrains the *shape* of the model's reply at the
  # provider: the response is guaranteed to parse and to have these keys.
  #
  # It cannot constrain meaning. Nothing here stops the model returning
  # 2000 kcal for a gram of lettuce -- that is Nutrition::Extraction's job.
  class NutritionSchema < RubyLLM::Schema
    boolean :food_detected,
            description: "True if the image shows food or drink intended for consumption. " \
                         "False for anything else, including packaging with no visible food."

    array :items,
          description: "One entry per distinct food or drink visible. Empty when food_detected is false." do
      object do
        string :name,
               description: "Common English name of the food, e.g. 'grilled chicken breast'. " \
                            "No brand names unless clearly legible."

        number :grams,
               description: "Estimated edible weight of this portion in grams. Must be greater than 0."

        number :kcal,
               description: "Total calories for this portion, i.e. for the stated grams."

        number :protein_g, description: "Protein in grams for this portion."
        number :carbs_g,   description: "Carbohydrate in grams for this portion."
        number :fat_g,     description: "Fat in grams for this portion."

        number :confidence,
               description: "How confident you are in this item's identification and weight, from 0.0 to 1.0."
      end
    end

    string :notes,
           required: false,
           description: "Anything that limited the estimate: obscured food, unclear scale, ambiguous preparation."
  end
end
