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

ActiveRecord::Schema[7.1].define(version: 2025_12_30_231000) do
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

  create_table "catalog_items", force: :cascade do |t|
    t.bigint "sheet_config_id", null: false
    t.string "sheet_name", null: false
    t.integer "row_number", null: false
    t.string "code", null: false
    t.text "description"
    t.decimal "price", precision: 15, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_catalog_items_on_code"
    t.index ["sheet_config_id"], name: "index_catalog_items_on_sheet_config_id"
  end

  create_table "catalog_types", force: :cascade do |t|
    t.string "name", null: false
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_catalog_types_on_name", unique: true
  end

  create_table "catalogs", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "catalog_type_id", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["catalog_type_id"], name: "index_catalogs_on_catalog_type_id"
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
    t.index ["catalog_id", "sheet_name"], name: "index_sheet_configs_on_catalog_id_and_sheet_name", unique: true
    t.index ["catalog_id"], name: "index_sheet_configs_on_catalog_id"
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
  add_foreign_key "catalog_items", "sheet_configs", on_delete: :cascade
  add_foreign_key "catalogs", "catalog_types"
  add_foreign_key "catalogs", "users"
  add_foreign_key "sheet_configs", "catalogs", on_delete: :cascade
end
