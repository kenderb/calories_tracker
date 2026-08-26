class CreateMealItems < ActiveRecord::Migration[8.1]
  def change
    create_table :meal_items do |t|
      t.references :meal, null: false, foreign_key: true

      t.string :food_name, null: false
      t.string :normalized_name, null: false
      t.decimal :grams, precision: 8, scale: 2, null: false
      t.decimal :confidence, precision: 4, scale: 3

      # As reported by the model, for this item's `grams`.
      t.decimal :kcal, precision: 8, scale: 2, null: false
      t.decimal :protein_g, precision: 8, scale: 2, null: false
      t.decimal :carbs_g, precision: 8, scale: 2, null: false
      t.decimal :fat_g, precision: 8, scale: 2, null: false

      # The same figures normalised to 100g. This is the basis a future scaling
      # service uses to answer "how much is in 90g?" without another model call.
      t.decimal :kcal_per_100g, precision: 8, scale: 2, null: false
      t.decimal :protein_per_100g, precision: 8, scale: 2, null: false
      t.decimal :carbs_per_100g, precision: 8, scale: 2, null: false
      t.decimal :fat_per_100g, precision: 8, scale: 2, null: false

      t.timestamps
    end

    add_index :meal_items, :normalized_name
  end
end
