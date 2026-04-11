class CreateBulkUploads < ActiveRecord::Migration[7.1]
  def change
    create_table :bulk_uploads do |t|
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: 'pending'
      t.integer :total, null: false, default: 0
      t.integer :processed, null: false, default: 0
      t.jsonb :results, null: false, default: []

      t.timestamps
    end
    
    add_index :bulk_uploads, :status
  end
end
