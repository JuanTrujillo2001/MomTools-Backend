class CreateCartItems < ActiveRecord::Migration[7.1]
  def change
    create_table :cart_items do |t|
      t.references :user, null: false, foreign_key: true
      t.references :supplier, null: false, foreign_key: true
      t.references :catalog_item, null: false, foreign_key: true
      t.integer :quantity, null: false, default: 1
      t.integer :status, null: false, default: 0
      t.datetime :ordered_at

      t.timestamps
    end

    add_index :cart_items, [:user_id, :catalog_item_id], unique: true
  end
end
