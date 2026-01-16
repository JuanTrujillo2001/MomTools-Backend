class CreateSuppliers < ActiveRecord::Migration[7.1]
  def change
    create_table :suppliers do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :phone
      t.string :email

      t.timestamps
    end
  end
end

