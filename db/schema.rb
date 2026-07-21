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

ActiveRecord::Schema[7.0].define(version: 2026_07_21_012425) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pgcrypto"
  enable_extension "plpgsql"

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.string "name", null: false
    t.text "body"
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

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
    t.index ["owner_id", "owner_type"], name: "index_activities_on_owner_id_and_owner_type"
    t.index ["owner_type", "owner_id"], name: "index_activities_on_owner_type_and_owner_id"
    t.index ["recipient_id", "recipient_type"], name: "index_activities_on_recipient_id_and_recipient_type"
    t.index ["recipient_type", "recipient_id"], name: "index_activities_on_recipient_type_and_recipient_id"
    t.index ["trackable_id", "trackable_type"], name: "index_activities_on_trackable_id_and_trackable_type"
    t.index ["trackable_type", "trackable_id"], name: "index_activities_on_trackable_type_and_trackable_id"
  end

  create_table "agenda_items", force: :cascade do |t|
    t.bigint "gathering_id", null: false
    t.bigint "author_id", null: false
    t.string "title", null: false
    t.integer "position", default: 0, null: false
    t.boolean "completed", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.integer "list", default: 0, null: false
    t.bigint "carrier_id"
    t.index ["author_id"], name: "index_agenda_items_on_author_id"
    t.index ["carrier_id"], name: "index_agenda_items_on_carrier_id"
    t.index ["gathering_id", "list", "position"], name: "index_agenda_items_on_gathering_id_and_list_and_position"
    t.index ["gathering_id", "position"], name: "index_agenda_items_on_gathering_id_and_position"
    t.index ["gathering_id"], name: "index_agenda_items_on_gathering_id"
  end

  create_table "booking_page_views", force: :cascade do |t|
    t.bigint "booking_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_id"], name: "index_booking_page_views_on_booking_id"
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
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.string "booking_type"
    t.index ["lodging_id"], name: "index_bookings_on_lodging_id"
  end

  create_table "bundles", force: :cascade do |t|
    t.string "name"
    t.integer "position"
    t.bigint "project_id"
    t.bigint "team_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_bundles_on_project_id"
    t.index ["team_id"], name: "index_bundles_on_team_id"
  end

  create_table "camping_bookings", force: :cascade do |t|
    t.string "firstname"
    t.string "lastname"
    t.string "email"
    t.string "phone"
    t.string "group_name"
    t.date "from_date"
    t.date "to_date"
    t.integer "people", default: 1, null: false
    t.string "kind", default: "tente", null: false
    t.string "status"
    t.integer "price_cents"
    t.string "token"
    t.text "notes"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_camping_bookings_on_deleted_at"
    t.index ["from_date", "to_date"], name: "index_camping_bookings_on_from_date_and_to_date"
  end

  create_table "coworking_packs", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.integer "days_total", null: false
    t.integer "price_cents", default: 0, null: false
    t.datetime "purchased_at", null: false
    t.datetime "expires_at", null: false
    t.string "payment_method", null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_coworking_packs_on_customer_id"
    t.index ["deleted_at"], name: "index_coworking_packs_on_deleted_at"
    t.index ["expires_at"], name: "index_coworking_packs_on_expires_at"
  end

  create_table "coworking_reservations", force: :cascade do |t|
    t.bigint "coworking_pack_id", null: false
    t.bigint "customer_id", null: false
    t.date "date", null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["coworking_pack_id"], name: "index_coworking_reservations_on_coworking_pack_id"
    t.index ["customer_id"], name: "index_coworking_reservations_on_customer_id"
    t.index ["date"], name: "index_coworking_reservations_on_date"
    t.index ["deleted_at"], name: "index_coworking_reservations_on_deleted_at"
  end

  create_table "customers", force: :cascade do |t|
    t.string "first_name"
    t.string "last_name"
    t.citext "email"
    t.string "phone"
    t.string "customer_type", default: "individual", null: false
    t.string "organization_name"
    t.string "vat_number"
    t.string "peppol_id"
    t.string "address_line"
    t.string "address_zip"
    t.string "address_city"
    t.string "address_country"
    t.string "language", default: "fr", null: false
    t.string "stripe_customer_id"
    t.boolean "marketing_consent", default: false, null: false
    t.boolean "nps_eligible", default: false, null: false
    t.bigint "human_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_type"], name: "index_customers_on_customer_type"
    t.index ["email"], name: "index_customers_on_email_unique_live", unique: true, where: "(deleted_at IS NULL)"
    t.index ["human_id"], name: "index_customers_on_human_id"
  end

  create_table "cycle_actions", force: :cascade do |t|
    t.string "label", null: false
    t.decimal "hours", precision: 5, scale: 2
    t.integer "category", default: 0, null: false
    t.boolean "completed", default: false
    t.bigint "human_id", null: false
    t.bigint "delegate_to_human_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "position", default: 0, null: false
    t.datetime "archived_at"
    t.index ["category"], name: "index_cycle_actions_on_category"
    t.index ["completed"], name: "index_cycle_actions_on_completed"
    t.index ["delegate_to_human_id"], name: "index_cycle_actions_on_delegate_to_human_id"
    t.index ["human_id", "archived_at"], name: "index_cycle_actions_on_human_id_and_archived_at"
    t.index ["human_id", "category", "position"], name: "index_cycle_actions_on_human_id_and_category_and_position"
    t.index ["human_id"], name: "index_cycle_actions_on_human_id"
  end

  create_table "cycles", force: :cascade do |t|
    t.string "name", null: false
    t.date "start_date", null: false
    t.date "end_date", null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["start_date", "end_date"], name: "index_cycles_on_start_date_and_end_date"
  end

  create_table "decisions", force: :cascade do |t|
    t.string "title", null: false
    t.string "summary", null: false
    t.date "taken_at", null: false
    t.bigint "recorded_by_id", null: false
    t.bigint "gathering_id"
    t.bigint "agenda_item_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.index ["agenda_item_id"], name: "index_decisions_on_agenda_item_id"
    t.index ["gathering_id"], name: "index_decisions_on_gathering_id"
    t.index ["recorded_by_id"], name: "index_decisions_on_recorded_by_id"
    t.index ["taken_at"], name: "index_decisions_on_taken_at", order: :desc
  end

  create_table "event_categories", force: :cascade do |t|
    t.string "name"
    t.string "color"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at", precision: nil
  end

  create_table "events", force: :cascade do |t|
    t.string "name"
    t.bigint "event_category_id", null: false
    t.datetime "starts_at"
    t.datetime "ends_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at", precision: nil
    t.string "url"
    t.integer "sales_amount_cents"
    t.integer "attendees"
    t.text "notes"
    t.string "status"
    t.index ["event_category_id"], name: "index_events_on_event_category_id"
  end

  create_table "experience_availabilities", force: :cascade do |t|
    t.bigint "experience_id", null: false
    t.date "available_on"
    t.string "starts_at"
    t.integer "duration_minutes"
    t.integer "max_participants"
    t.string "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["experience_id"], name: "index_experience_availabilities_on_experience_id"
  end

  create_table "experience_bookings", force: :cascade do |t|
    t.bigint "experience_availability_id", null: false
    t.bigint "stay_id", null: false
    t.integer "participants"
    t.string "status"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "refusal_reason"
    t.index ["experience_availability_id"], name: "index_experience_bookings_on_experience_availability_id"
    t.index ["stay_id"], name: "index_experience_bookings_on_stay_id"
  end

  create_table "experiences", force: :cascade do |t|
    t.string "name"
    t.bigint "human_id"
    t.string "summary"
    t.text "description"
    t.string "photo"
    t.datetime "deleted_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "price_cents"
    t.integer "fixed_price_cents", default: 0
    t.integer "min_participants"
    t.integer "max_participants"
    t.string "duration"
    t.decimal "duration_hours", precision: 4, scale: 2
    t.string "color"
    t.index ["human_id"], name: "index_experiences_on_human_id"
  end

  create_table "gathering_action_humans", force: :cascade do |t|
    t.bigint "gathering_action_id", null: false
    t.bigint "human_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["gathering_action_id", "human_id"], name: "index_gathering_action_humans_uniqueness", unique: true
    t.index ["gathering_action_id"], name: "index_gathering_action_humans_on_gathering_action_id"
    t.index ["human_id"], name: "index_gathering_action_humans_on_human_id"
  end

  create_table "gathering_actions", force: :cascade do |t|
    t.bigint "gathering_id", null: false
    t.string "label", null: false
    t.boolean "completed", default: false, null: false
    t.datetime "completed_at"
    t.integer "position", default: 0, null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_gathering_actions_on_deleted_at"
    t.index ["gathering_id", "position"], name: "index_gathering_actions_on_gathering_id_and_position"
    t.index ["gathering_id"], name: "index_gathering_actions_on_gathering_id"
  end

  create_table "gathering_categories", force: :cascade do |t|
    t.string "name", null: false
    t.string "color", null: false
    t.time "default_start_time"
    t.integer "default_duration_minutes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
  end

  create_table "gatherings", force: :cascade do |t|
    t.string "name"
    t.bigint "gathering_category_id", null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.string "location"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.index ["gathering_category_id"], name: "index_gatherings_on_gathering_category_id"
    t.index ["starts_at", "ends_at"], name: "index_gatherings_on_starts_at_and_ends_at"
  end

  create_table "human_roles", force: :cascade do |t|
    t.bigint "human_id", null: false
    t.bigint "role_id", null: false
    t.date "date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "status", default: 1, null: false
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
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status", default: "active"
    t.boolean "cycle_active", default: false
    t.boolean "roles_enabled", default: true, null: false
  end

  create_table "humans_tasks", id: false, force: :cascade do |t|
    t.bigint "task_id", null: false
    t.bigint "human_id", null: false
    t.index ["human_id", "task_id"], name: "index_humans_tasks_on_human_id_and_task_id"
    t.index ["task_id", "human_id"], name: "index_humans_tasks_on_task_id_and_human_id"
  end

  create_table "lodging_compositions", force: :cascade do |t|
    t.bigint "composite_lodging_id", null: false
    t.bigint "component_lodging_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["component_lodging_id"], name: "index_lodging_compositions_on_component_lodging_id"
    t.index ["composite_lodging_id", "component_lodging_id"], name: "index_lodging_compositions_unique_pair", unique: true
    t.index ["composite_lodging_id"], name: "index_lodging_compositions_on_composite_lodging_id"
  end

  create_table "lodging_rooms", force: :cascade do |t|
    t.bigint "lodging_id", null: false
    t.bigint "room_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lodging_id"], name: "index_lodging_rooms_on_lodging_id"
    t.index ["room_id"], name: "index_lodging_rooms_on_room_id"
  end

  create_table "lodgings", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "summary"
    t.integer "price_night_cents", default: 0, null: false
    t.boolean "party_hall_availability"
    t.integer "weekend_discount_cents", default: 0, null: false
    t.datetime "deleted_at", precision: nil
    t.boolean "show_on_reports", default: true
    t.boolean "available_for_bookings"
  end

  create_table "meal_orders", force: :cascade do |t|
    t.bigint "stay_id", null: false
    t.string "kind"
    t.date "date"
    t.integer "people", default: 1, null: false
    t.integer "price_cents"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_meal_orders_on_deleted_at"
    t.index ["stay_id"], name: "index_meal_orders_on_stay_id"
  end

  create_table "notes", force: :cascade do |t|
    t.text "body"
    t.date "date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at", precision: nil
    t.string "color"
  end

  create_table "payment_versions", force: :cascade do |t|
    t.string "item_type", null: false
    t.uuid "item_id", null: false
    t.string "event", null: false
    t.string "whodunnit"
    t.text "object"
    t.datetime "created_at"
    t.text "object_changes"
    t.index ["item_type", "item_id"], name: "index_payment_versions_on_item_type_and_item_id"
  end

  create_table "payments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.bigint "booking_id"
    t.string "payment_method"
    t.string "status"
    t.datetime "deleted_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "amount_cents", default: 0, null: false
    t.string "stripe_checkout_session_id"
    t.string "stripe_payment_intent_id"
    t.bigint "stay_id"
    t.bigint "space_booking_id"
    t.bigint "coworking_pack_id"
    t.index ["booking_id"], name: "index_payments_on_booking_id"
    t.index ["coworking_pack_id"], name: "index_payments_on_coworking_pack_id"
    t.index ["id"], name: "index_payments_on_id", unique: true
    t.index ["space_booking_id"], name: "index_payments_on_space_booking_id"
    t.index ["stay_id"], name: "index_payments_on_stay_id"
  end

  create_table "products", force: :cascade do |t|
    t.string "name"
    t.integer "stock"
    t.string "photo"
    t.text "description"
    t.datetime "deleted_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "price_cents"
  end

  create_table "projects", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.date "due_date"
    t.bigint "human_id", null: false
    t.datetime "deleted_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["human_id"], name: "index_projects_on_human_id"
  end

  create_table "rates", force: :cascade do |t|
    t.string "key", null: false
    t.integer "amount_cents", default: 0, null: false
    t.string "label"
    t.string "unit", default: "cents", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_rates_on_key", unique: true
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
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "date"
    t.datetime "deleted_at", precision: nil
    t.index ["booking_id"], name: "index_reservations_on_booking_id"
    t.index ["room_id"], name: "index_reservations_on_room_id"
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
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "price_cents"
    t.index ["human_id"], name: "index_services_on_human_id"
  end

  create_table "settings", force: :cascade do |t|
    t.string "key", null: false
    t.string "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_settings_on_key", unique: true
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
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.index ["event_id"], name: "index_space_bookings_on_event_id"
  end

  create_table "space_reservations", force: :cascade do |t|
    t.bigint "space_booking_id", null: false
    t.bigint "space_id", null: false
    t.date "date"
    t.string "duration"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at", precision: nil
    t.index ["space_booking_id"], name: "index_space_reservations_on_space_booking_id"
    t.index ["space_id"], name: "index_space_reservations_on_space_id"
  end

  create_table "spaces", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "code"
    t.datetime "deleted_at", precision: nil
    t.integer "position", default: 999
    t.integer "capacity", default: 1, null: false
  end

  create_table "stay_items", force: :cascade do |t|
    t.bigint "stay_id", null: false
    t.string "bookable_type", null: false
    t.bigint "bookable_id", null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bookable_type", "bookable_id"], name: "index_stay_items_on_bookable_type_and_bookable_id"
    t.index ["stay_id", "bookable_type", "bookable_id"], name: "index_stay_items_on_stay_and_bookable_unique_live", unique: true, where: "(deleted_at IS NULL)"
    t.index ["stay_id"], name: "index_stay_items_on_stay_id"
  end

  create_table "stays", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.date "arrival_date"
    t.date "departure_date"
    t.string "status"
    t.integer "total_amount_cents", default: 0, null: false
    t.text "notes"
    t.string "legacy_origin"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "source", default: "reservation", null: false
    t.string "activity_selection_token"
    t.datetime "activity_email_sent_at"
    t.string "token"
    t.string "payment_status", default: "pending", null: false
    t.datetime "balance_reminder_sent_at"
    t.integer "price_override_cents"
    t.index ["activity_selection_token"], name: "index_stays_on_activity_selection_token"
    t.index ["customer_id"], name: "index_stays_on_customer_id"
    t.index ["legacy_origin"], name: "index_stays_on_legacy_origin_unique_live", unique: true, where: "((legacy_origin IS NOT NULL) AND (deleted_at IS NULL))"
    t.index ["source"], name: "index_stays_on_source"
    t.index ["token"], name: "index_stays_on_token", unique: true
  end

  create_table "stripe_events", force: :cascade do |t|
    t.string "webhook_id"
    t.string "event_type"
    t.string "object_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "subscriptions", force: :cascade do |t|
    t.string "email"
    t.boolean "newsletter"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "tasks", force: :cascade do |t|
    t.string "name"
    t.bigint "project_id", null: false
    t.text "description"
    t.string "status"
    t.date "due_date"
    t.datetime "deleted_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "bundle_id", null: false
    t.index ["bundle_id"], name: "index_tasks_on_bundle_id"
    t.index ["project_id"], name: "index_tasks_on_project_id"
  end

  create_table "teams", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.datetime "deleted_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "unavailabilities", force: :cascade do |t|
    t.date "date"
    t.bigint "lodging_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lodging_id"], name: "index_unavailabilities_on_lodging_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "human_id"
    t.boolean "restricted_to_experiences", default: false, null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["human_id"], name: "index_users_on_human_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "van_bookings", force: :cascade do |t|
    t.string "firstname"
    t.string "lastname"
    t.string "email"
    t.string "phone"
    t.string "group_name"
    t.date "from_date"
    t.date "to_date"
    t.integer "vehicles", default: 1, null: false
    t.string "status"
    t.integer "price_cents"
    t.string "token"
    t.text "notes"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_van_bookings_on_deleted_at"
    t.index ["from_date", "to_date"], name: "index_van_bookings_on_from_date_and_to_date"
  end

  create_table "versions", force: :cascade do |t|
    t.string "item_type", null: false
    t.bigint "item_id", null: false
    t.string "event", null: false
    t.string "whodunnit"
    t.text "object"
    t.datetime "created_at"
    t.text "object_changes"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  create_table "watchman_notes", force: :cascade do |t|
    t.date "date"
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["date"], name: "index_watchman_notes_on_date"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agenda_items", "gatherings"
  add_foreign_key "agenda_items", "humans", column: "author_id"
  add_foreign_key "agenda_items", "humans", column: "carrier_id"
  add_foreign_key "booking_page_views", "bookings"
  add_foreign_key "bookings", "lodgings"
  add_foreign_key "bundles", "projects"
  add_foreign_key "bundles", "teams"
  add_foreign_key "coworking_packs", "customers"
  add_foreign_key "coworking_reservations", "coworking_packs"
  add_foreign_key "coworking_reservations", "customers"
  add_foreign_key "customers", "humans"
  add_foreign_key "cycle_actions", "humans"
  add_foreign_key "cycle_actions", "humans", column: "delegate_to_human_id"
  add_foreign_key "decisions", "agenda_items", on_delete: :nullify
  add_foreign_key "decisions", "gatherings", on_delete: :nullify
  add_foreign_key "decisions", "humans", column: "recorded_by_id"
  add_foreign_key "events", "event_categories"
  add_foreign_key "experience_availabilities", "experiences"
  add_foreign_key "experience_bookings", "experience_availabilities"
  add_foreign_key "experience_bookings", "stays"
  add_foreign_key "experiences", "humans"
  add_foreign_key "gathering_action_humans", "gathering_actions"
  add_foreign_key "gathering_action_humans", "humans"
  add_foreign_key "gathering_actions", "gatherings"
  add_foreign_key "gatherings", "gathering_categories"
  add_foreign_key "human_roles", "humans"
  add_foreign_key "human_roles", "roles"
  add_foreign_key "lodging_compositions", "lodgings", column: "component_lodging_id"
  add_foreign_key "lodging_compositions", "lodgings", column: "composite_lodging_id"
  add_foreign_key "lodging_rooms", "lodgings"
  add_foreign_key "lodging_rooms", "rooms"
  add_foreign_key "meal_orders", "stays"
  add_foreign_key "payments", "bookings"
  add_foreign_key "payments", "coworking_packs"
  add_foreign_key "payments", "space_bookings"
  add_foreign_key "payments", "stays"
  add_foreign_key "projects", "humans"
  add_foreign_key "reservations", "bookings"
  add_foreign_key "reservations", "rooms"
  add_foreign_key "services", "humans"
  add_foreign_key "space_bookings", "events"
  add_foreign_key "space_reservations", "space_bookings"
  add_foreign_key "space_reservations", "spaces"
  add_foreign_key "stay_items", "stays"
  add_foreign_key "stays", "customers"
  add_foreign_key "tasks", "bundles"
  add_foreign_key "tasks", "projects"
  add_foreign_key "unavailabilities", "lodgings"
  add_foreign_key "users", "humans"
end
