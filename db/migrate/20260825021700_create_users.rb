class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :name

      # Looked up on every request, so it is indexed and stored raw rather than
      # digested. See User for the tradeoff.
      t.string :api_token, null: false

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :api_token, unique: true
  end
end
