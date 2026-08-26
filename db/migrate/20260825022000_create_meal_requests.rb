class CreateMealRequests < ActiveRecord::Migration[8.1]
  # Who asked for which meal. Meals themselves are global and reusable, so
  # attribution lives here rather than as a user_id on meals.
  def change
    create_table :meal_requests do |t|
      t.references :user, null: false, foreign_key: true
      t.references :meal, null: false, foreign_key: true

      # True when this request was served from an existing analysis rather than
      # triggering a new one. Makes the cache hit rate directly queryable.
      t.boolean :reused, null: false, default: false

      t.timestamps
    end

    add_index :meal_requests, [ :user_id, :created_at ]
  end
end
