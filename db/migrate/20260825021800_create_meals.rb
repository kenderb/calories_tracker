class CreateMeals < ActiveRecord::Migration[8.1]
  def change
    create_table :meals do |t|
      # SHA-256 of the uploaded image bytes. This is the reuse key: the same
      # photo, uploaded by anyone, resolves to this row instead of a new
      # analysis. Unique so two concurrent uploads cannot both spend a call.
      t.string :image_checksum, null: false

      t.string :status, null: false, default: "pending"

      # Provenance of the extraction, so a result can always be traced back to
      # the model that produced it.
      t.string :provider
      t.string :model_id
      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :cost_millicents
      t.integer :latency_ms
      t.datetime :analyzed_at

      # The provider's full response, kept on success and failure alike so a bad
      # extraction can be debugged without paying for the call twice.
      t.jsonb :raw_response

      t.string :failure_kind
      t.text :failure_reason

      t.timestamps
    end

    add_index :meals, :image_checksum, unique: true
    add_index :meals, :status
  end
end
