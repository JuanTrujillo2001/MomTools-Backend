# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_04_25_143500) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_trgm"
  enable_extension "plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "bulk_uploads", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "status", default: "pending", null: false
    t.integer "total", default: 0, null: false
    t.integer "processed", default: 0, null: false
    t.jsonb "results", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["status"], name: "index_bulk_uploads_on_status"
    t.index ["user_id"], name: "index_bulk_uploads_on_user_id"
  end

  create_table "cart_items", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "supplier_id", null: false
    t.bigint "catalog_item_id", null: false
    t.integer "quantity", default: 1, null: false
    t.integer "status", default: 0, null: false
    t.datetime "ordered_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["catalog_item_id"], name: "index_cart_items_on_catalog_item_id"
    t.index ["supplier_id"], name: "index_cart_items_on_supplier_id"
    t.index ["user_id", "catalog_item_id"], name: "index_cart_items_on_user_id_and_catalog_item_id", unique: true
    t.index ["user_id"], name: "index_cart_items_on_user_id"
  end

  create_table "catalog_items", force: :cascade do |t|
    t.bigint "sheet_config_id", null: false
    t.string "sheet_name", null: false
    t.integer "row_number", null: false
    t.string "code", null: false
    t.text "description"
    t.decimal "price", precision: 15, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "brand"
    t.index ["code"], name: "index_catalog_items_on_code"
    t.index ["sheet_config_id"], name: "index_catalog_items_on_sheet_config_id"
  end

  create_table "catalogs", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "supplier_id"
    t.string "pdf_to_excel_status"
    t.text "pdf_to_excel_error"
    t.datetime "pdf_to_excel_started_at"
    t.datetime "pdf_to_excel_finished_at"
    t.index ["pdf_to_excel_status"], name: "index_catalogs_on_pdf_to_excel_status"
    t.index ["supplier_id"], name: "index_catalogs_on_supplier_id"
    t.index ["user_id"], name: "index_catalogs_on_user_id"
  end

  create_table "sheet_configs", force: :cascade do |t|
    t.bigint "catalog_id", null: false
    t.string "sheet_name", null: false
    t.string "code_columns", default: [], null: false, array: true
    t.string "description_columns", default: [], null: false, array: true
    t.string "price_columns", default: [], null: false, array: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "brand_columns", default: [], null: false, array: true
    t.index ["catalog_id", "sheet_name"], name: "index_sheet_configs_on_catalog_id_and_sheet_name", unique: true
    t.index ["catalog_id"], name: "index_sheet_configs_on_catalog_id"
  end

  create_table "suppliers", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "phone"
    t.string "email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_suppliers_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "bulk_uploads", "users"
  add_foreign_key "cart_items", "catalog_items"
  add_foreign_key "cart_items", "suppliers"
  add_foreign_key "cart_items", "users"
  add_foreign_key "catalog_items", "sheet_configs", on_delete: :cascade
  add_foreign_key "catalogs", "suppliers"
  add_foreign_key "catalogs", "users"
  add_foreign_key "sheet_configs", "catalogs", on_delete: :cascade
  add_foreign_key "suppliers", "users"
end
