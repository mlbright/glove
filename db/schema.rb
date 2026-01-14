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

ActiveRecord::Schema[8.1].define(version: 2026_01_14_030752) do
  create_table "accounts", force: :cascade do |t|
    t.integer "account_type", default: 0, null: false
    t.datetime "archived_at"
    t.string "color"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_accounts_on_name", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "tags", force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["color"], name: "index_tags_on_color"
    t.index ["user_id", "slug"], name: "index_tags_on_user_id_and_slug", unique: true
    t.index ["user_id"], name: "index_tags_on_user_id"
  end

  create_table "transaction_revisions", force: :cascade do |t|
    t.string "action", null: false
    t.json "change_log", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "recorded_at", null: false
    t.integer "transaction_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["transaction_id", "recorded_at"], name: "index_transaction_revisions_on_transaction_id_and_recorded_at"
    t.index ["transaction_id"], name: "index_transaction_revisions_on_transaction_id"
    t.index ["user_id"], name: "index_transaction_revisions_on_user_id"
  end

  create_table "transaction_tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "tag_id", null: false
    t.integer "transaction_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tag_id"], name: "index_transaction_tags_on_tag_id"
    t.index ["transaction_id", "tag_id"], name: "index_transaction_tags_on_transaction_id_and_tag_id", unique: true
    t.index ["transaction_id"], name: "index_transaction_tags_on_transaction_id"
  end

  create_table "transactions", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "amount_cents", null: false
    t.integer "balance_cents"
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "entry_type", default: 0, null: false
    t.boolean "excludes_from_balance", default: false, null: false
    t.text "notes"
    t.datetime "occurred_on", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_transactions_on_account_id"
    t.index ["account_id"], name: "index_transactions_on_account_id_and_occurred_on"
    t.index ["entry_type"], name: "index_transactions_on_entry_type"
  end

  create_table "users", force: :cascade do |t|
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "email", default: "", null: false
    t.datetime "last_sign_in_at"
    t.string "name"
    t.string "provider"
    t.datetime "remember_created_at"
    t.integer "sign_in_count", default: 0, null: false
    t.string "uid"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "tags", "users"
  add_foreign_key "transaction_revisions", "users"
  add_foreign_key "transaction_tags", "tags"
  add_foreign_key "transaction_tags", "transactions"
  add_foreign_key "transactions", "accounts"
end
