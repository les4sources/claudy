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

ActiveRecord::Schema[7.0].define(version: 2023_11_20_160330) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.string "name", null: false
    t.text "body"
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", precision: nil, null: false
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", precision: nil, null: false
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
  end

  create_table "activities", id: :serial, force: :cascade do |t|
    t.string "trackable_type"
    t.integer "trackable_id"
    t.string "owner_type"
    t.integer "owner_id"
    t.string "key"
    t.text "parameters"
    t.string "recipient_type"
    t.integer "recipient_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "bookings", force: :cascade do |t|
    t.string "firstname"
    t.string "lastname"
    t.string "phone"
    t.string "email"
    t.date "from_date"
    t.date "to_date"
    t.string "status"
    t.integer "adults"
    t.integer "children"
    t.string "payment_status"
    t.string "payment_method"
    t.boolean "bedsheets"
    t.boolean "towels"
    t.text "notes"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "price_cents"
    t.string "invoice_status"
    t.string "contract_status"
    t.string "estimated_arrival"
    t.boolean "option_babysitting"
    t.boolean "option_partyhall"
    t.boolean "option_bread"
    t.text "comments"
    t.string "tier"
    t.bigint "lodging_id"
    t.boolean "option_discgolf"
    t.integer "shown_price_cents", default: 0, null: false
    t.string "token"
    t.string "platform"
    t.string "group_name"
    t.integer "babies", default: 0
    t.text "public_notes"
    t.string "departure_time"
    t.boolean "option_pizza_party"
    t.datetime "deleted_at", precision: nil
    t.boolean "wifi", default: false
  end

  create_table "bundles", force: :cascade do |t|
    t.string "name"
    t.integer "position"
    t.bigint "project_id"
    t.bigint "team_id"
    t.datetime "deleted_at", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "event_categories", force: :cascade do |t|
    t.string "name"
    t.string "color"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.datetime "deleted_at", precision: nil
  end

  create_table "events", force: :cascade do |t|
    t.string "name"
    t.bigint "event_category_id", null: false
    t.datetime "starts_at", precision: nil
    t.datetime "ends_at", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.datetime "deleted_at", precision: nil
    t.string "url"
  end

  create_table "experiences", force: :cascade do |t|
    t.string "name"
    t.bigint "human_id"
    t.string "summary"
    t.text "description"
    t.string "photo"
    t.datetime "deleted_at", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "price_cents"
    t.integer "fixed_price_cents", default: 0
    t.integer "min_participants"
    t.integer "max_participants"
    t.string "duration"
  end

  create_table "human_roles", force: :cascade do |t|
    t.bigint "human_id", null: false
    t.bigint "role_id", null: false
    t.date "date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["human_id"], name: "index_human_roles_on_human_id"
    t.index ["role_id"], name: "index_human_roles_on_role_id"
  end

  create_table "humans", force: :cascade do |t|
    t.string "name"
    t.string "email"
    t.string "photo"
    t.string "summary"
    t.text "description"
    t.datetime "deleted_at", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "humans_tasks", id: false, force: :cascade do |t|
    t.bigint "task_id", null: false
    t.bigint "human_id", null: false
  end

  create_table "lodging_rooms", force: :cascade do |t|
    t.bigint "lodging_id", null: false
    t.bigint "room_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "lodgings", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "summary"
    t.integer "price_night_cents", default: 0, null: false
    t.boolean "party_hall_availability"
    t.integer "weekend_discount_cents", default: 0, null: false
    t.datetime "deleted_at", precision: nil
  end

  create_table "notes", force: :cascade do |t|
    t.text "body"
    t.date "date"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.datetime "deleted_at", precision: nil
    t.string "color"
  end

  create_table "products", force: :cascade do |t|
    t.string "name"
    t.integer "stock"
    t.string "photo"
    t.text "description"
    t.datetime "deleted_at", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "price_cents"
  end

  create_table "projects", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.date "due_date"
    t.bigint "human_id", null: false
    t.datetime "deleted_at", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "rental_items", force: :cascade do |t|
    t.string "name"
    t.integer "stock"
    t.string "photo"
    t.text "description"
    t.datetime "deleted_at"
    t.integer "price_cents"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "reservations", force: :cascade do |t|
    t.bigint "booking_id", null: false
    t.bigint "room_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.date "date"
    t.datetime "deleted_at", precision: nil
  end

  create_table "roles", force: :cascade do |t|
    t.string "name"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "role_team", default: []
    t.index ["role_team"], name: "index_roles_on_role_team", using: :gin
  end

  create_table "rooms", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "level"
    t.string "code"
    t.datetime "deleted_at", precision: nil
  end

  create_table "services", force: :cascade do |t|
    t.string "name"
    t.bigint "human_id"
    t.string "summary"
    t.text "description"
    t.string "photo"
    t.datetime "deleted_at", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "price_cents"
  end

  create_table "space_bookings", force: :cascade do |t|
    t.string "firstname"
    t.string "lastname"
    t.string "group_name"
    t.string "phone"
    t.string "email"
    t.date "from_date"
    t.date "to_date"
    t.string "status"
    t.string "tier"
    t.string "payment_status"
    t.string "invoice_status"
    t.string "contract_status"
    t.text "notes"
    t.string "token"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "price_cents"
    t.string "payment_method"
    t.bigint "event_id"
    t.text "public_notes"
    t.integer "paid_amount_cents"
    t.integer "deposit_amount_cents"
    t.string "persons"
    t.string "arrival_time"
    t.string "departure_time"
    t.boolean "option_kitchenware", default: false
    t.boolean "option_beamer", default: false
    t.boolean "option_wifi", default: false
    t.boolean "option_tables", default: false
    t.integer "advance_amount_cents"
    t.datetime "deleted_at", precision: nil
  end

  create_table "space_reservations", force: :cascade do |t|
    t.bigint "space_booking_id", null: false
    t.bigint "space_id", null: false
    t.date "date"
    t.string "duration"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.datetime "deleted_at", precision: nil
  end

  create_table "spaces", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "code"
    t.datetime "deleted_at", precision: nil
  end

  create_table "subscriptions", force: :cascade do |t|
    t.string "email"
    t.boolean "newsletter"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "tasks", force: :cascade do |t|
    t.string "name"
    t.bigint "project_id", null: false
    t.text "description"
    t.string "status"
    t.date "due_date"
    t.datetime "deleted_at", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.bigint "bundle_id", null: false
  end

  create_table "teams", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.datetime "deleted_at", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at", precision: nil
    t.datetime "remember_created_at", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.bigint "human_id"
  end

  create_table "versions", force: :cascade do |t|
    t.string "item_type", null: false
    t.bigint "item_id", null: false
    t.string "event", null: false
    t.string "whodunnit"
    t.text "object"
    t.datetime "created_at", precision: nil
    t.text "object_changes"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id", name: "active_storage_attachments_blob_id_fkey"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id", name: "active_storage_variant_records_blob_id_fkey"
  add_foreign_key "bookings", "lodgings", name: "bookings_lodging_id_fkey"
  add_foreign_key "bundles", "projects", name: "bundles_project_id_fkey"
  add_foreign_key "bundles", "teams", name: "bundles_team_id_fkey"
  add_foreign_key "events", "event_categories", name: "events_event_category_id_fkey"
  add_foreign_key "experiences", "humans", name: "experiences_human_id_fkey"
  add_foreign_key "human_roles", "humans"
  add_foreign_key "human_roles", "roles"
  add_foreign_key "lodging_rooms", "lodgings", name: "lodging_rooms_lodging_id_fkey"
  add_foreign_key "lodging_rooms", "rooms", name: "lodging_rooms_room_id_fkey"
  add_foreign_key "projects", "humans", name: "projects_human_id_fkey"
  add_foreign_key "reservations", "bookings", name: "reservations_booking_id_fkey"
  add_foreign_key "reservations", "rooms", name: "reservations_room_id_fkey"
  add_foreign_key "services", "humans", name: "services_human_id_fkey"
  add_foreign_key "space_bookings", "events", name: "space_bookings_event_id_fkey"
  add_foreign_key "space_reservations", "space_bookings", name: "space_reservations_space_booking_id_fkey"
  add_foreign_key "space_reservations", "spaces", name: "space_reservations_space_id_fkey"
  add_foreign_key "tasks", "bundles", name: "tasks_bundle_id_fkey"
  add_foreign_key "tasks", "projects", name: "tasks_project_id_fkey"
  add_foreign_key "users", "humans", name: "users_human_id_fkey"
end
