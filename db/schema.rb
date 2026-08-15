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

ActiveRecord::Schema[8.1].define(version: 2026_08_15_040000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "account_entries", force: :cascade do |t|
    t.bigint "account_statement_id"
    t.bigint "amount_cents", null: false
    t.bigint "catalog_item_id"
    t.string "client_uuid"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.date "entry_date", null: false
    t.string "flow"
    t.string "idempotency_key"
    t.string "kind"
    t.string "label"
    t.datetime "locked_at"
    t.bigint "member_account_id", null: false
    t.bigint "paper_sheet_id"
    t.datetime "posted_at"
    t.string "price_basis"
    t.decimal "quantity", precision: 12, scale: 3
    t.bigint "reversal_of_id"
    t.string "source"
    t.integer "unit_price_cents"
    t.datetime "updated_at", null: false
    t.index ["account_statement_id"], name: "index_account_entries_on_account_statement_id"
    t.index ["catalog_item_id"], name: "index_account_entries_on_catalog_item_id"
    t.index ["client_uuid"], name: "index_account_entries_on_client_uuid", unique: true
    t.index ["deleted_at"], name: "index_account_entries_on_deleted_at"
    t.index ["idempotency_key"], name: "index_account_entries_on_idempotency_key", unique: true
    t.index ["member_account_id", "entry_date"], name: "index_account_entries_on_member_account_id_and_entry_date"
    t.index ["paper_sheet_id"], name: "index_account_entries_on_paper_sheet_id"
    t.index ["reversal_of_id"], name: "index_account_entries_on_reversal_of_id"
    t.check_constraint "amount_cents <> 0", name: "account_entries_amount_not_zero_check"
  end

  create_table "account_settlements", force: :cascade do |t|
    t.bigint "account_entry_id"
    t.bigint "amount_cents", null: false
    t.string "bank_reference"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "member_account_id", null: false
    t.string "method", default: "bank_transfer", null: false
    t.text "notes"
    t.string "received_channel", default: "bank", null: false
    t.date "received_on", null: false
    t.string "reference"
    t.datetime "updated_at", null: false
    t.index ["account_entry_id"], name: "index_account_settlements_on_account_entry_id"
    t.index ["deleted_at"], name: "index_account_settlements_on_deleted_at"
    t.index ["member_account_id"], name: "index_account_settlements_on_member_account_id"
    t.index ["received_on"], name: "index_account_settlements_on_received_on"
  end

  create_table "account_statements", force: :cascade do |t|
    t.bigint "closing_balance_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.bigint "credits_cents", default: 0, null: false
    t.bigint "debits_cents", default: 0, null: false
    t.datetime "deleted_at"
    t.datetime "issued_at"
    t.datetime "last_reminder_at"
    t.bigint "member_account_id", null: false
    t.bigint "opening_balance_cents", default: 0, null: false
    t.date "period_month", null: false
    t.integer "reminders_count", default: 0, null: false
    t.datetime "sent_at"
    t.string "status", default: "draft", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_account_statements_on_deleted_at"
    t.index ["member_account_id", "period_month"], name: "index_account_statements_on_member_account_id_and_period_month", unique: true
    t.index ["member_account_id"], name: "index_account_statements_on_member_account_id"
    t.index ["token"], name: "index_account_statements_on_token", unique: true
  end

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
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

  create_table "activities", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.string "key"
    t.integer "owner_id"
    t.string "owner_type"
    t.text "parameters"
    t.integer "recipient_id"
    t.string "recipient_type"
    t.integer "trackable_id"
    t.string "trackable_type"
    t.datetime "updated_at", precision: nil, null: false
    t.index ["owner_id", "owner_type"], name: "index_activities_on_owner_id_and_owner_type"
    t.index ["owner_type", "owner_id"], name: "index_activities_on_owner_type_and_owner_id"
    t.index ["recipient_id", "recipient_type"], name: "index_activities_on_recipient_id_and_recipient_type"
    t.index ["recipient_type", "recipient_id"], name: "index_activities_on_recipient_type_and_recipient_id"
    t.index ["trackable_id", "trackable_type"], name: "index_activities_on_trackable_id_and_trackable_type"
    t.index ["trackable_type", "trackable_id"], name: "index_activities_on_trackable_type_and_trackable_id"
  end

  create_table "agenda_items", force: :cascade do |t|
    t.bigint "author_id", null: false
    t.bigint "carrier_id"
    t.boolean "completed", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "gathering_id", null: false
    t.integer "list", default: 0, null: false
    t.integer "position", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_agenda_items_on_author_id"
    t.index ["carrier_id"], name: "index_agenda_items_on_carrier_id"
    t.index ["gathering_id", "list", "position"], name: "index_agenda_items_on_gathering_id_and_list_and_position"
    t.index ["gathering_id", "position"], name: "index_agenda_items_on_gathering_id_and_position"
    t.index ["gathering_id"], name: "index_agenda_items_on_gathering_id"
  end

  create_table "analytic_accounts", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "name", null: false
    t.bigint "team_id"
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_analytic_accounts_on_code", unique: true
    t.index ["deleted_at"], name: "index_analytic_accounts_on_deleted_at"
    t.index ["team_id"], name: "index_analytic_accounts_on_team_id"
  end

  create_table "booking_page_views", force: :cascade do |t|
    t.bigint "booking_id", null: false
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["booking_id"], name: "index_booking_page_views_on_booking_id"
  end

  create_table "bookings", force: :cascade do |t|
    t.integer "adults"
    t.integer "babies", default: 0
    t.boolean "bedsheets"
    t.string "booking_type"
    t.integer "children"
    t.text "comments"
    t.string "contract_status"
    t.datetime "created_at", null: false
    t.datetime "deleted_at", precision: nil
    t.string "departure_time"
    t.string "email"
    t.string "estimated_arrival"
    t.string "firstname"
    t.date "from_date"
    t.string "group_name"
    t.string "invoice_status"
    t.string "lastname"
    t.bigint "lodging_id"
    t.text "notes"
    t.boolean "option_babysitting"
    t.boolean "option_bread"
    t.boolean "option_discgolf"
    t.boolean "option_partyhall"
    t.boolean "option_pizza_party"
    t.string "payment_method"
    t.string "payment_status"
    t.string "phone"
    t.string "platform"
    t.integer "price_cents"
    t.text "public_notes"
    t.integer "shown_price_cents", default: 0, null: false
    t.string "status"
    t.string "tier"
    t.date "to_date"
    t.string "token"
    t.boolean "towels"
    t.datetime "updated_at", null: false
    t.boolean "wifi", default: false
    t.index ["lodging_id"], name: "index_bookings_on_lodging_id"
  end

  create_table "bundles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "name"
    t.integer "position"
    t.bigint "project_id"
    t.bigint "team_id"
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_bundles_on_project_id"
    t.index ["team_id"], name: "index_bundles_on_team_id"
  end

  create_table "camping_bookings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "email"
    t.string "firstname"
    t.date "from_date"
    t.string "group_name"
    t.string "kind", default: "tente", null: false
    t.string "lastname"
    t.text "notes"
    t.integer "people", default: 1, null: false
    t.string "phone"
    t.integer "price_cents"
    t.string "status"
    t.date "to_date"
    t.string "token"
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_camping_bookings_on_deleted_at"
    t.index ["from_date", "to_date"], name: "index_camping_bookings_on_from_date_and_to_date"
  end

  create_table "cash_accounts", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "general_account_id", null: false
    t.string "iban"
    t.string "kind", null: false
    t.bigint "legal_entity_id", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_cash_accounts_on_deleted_at"
    t.index ["general_account_id"], name: "index_cash_accounts_on_general_account_id"
    t.index ["legal_entity_id"], name: "index_cash_accounts_on_legal_entity_id"
    t.index ["name"], name: "index_cash_accounts_on_name", unique: true
  end

  create_table "cash_allocations", force: :cascade do |t|
    t.bigint "amount_cents", null: false
    t.bigint "analytic_account_id"
    t.bigint "cash_entry_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "document_id"
    t.string "document_type"
    t.bigint "general_account_id", null: false
    t.string "label"
    t.bigint "legal_entity_id", null: false
    t.bigint "team_id"
    t.datetime "updated_at", null: false
    t.index ["analytic_account_id"], name: "index_cash_allocations_on_analytic_account_id"
    t.index ["cash_entry_id"], name: "index_cash_allocations_on_cash_entry_id"
    t.index ["deleted_at"], name: "index_cash_allocations_on_deleted_at"
    t.index ["document_type", "document_id"], name: "index_cash_allocations_on_document_type_and_document_id"
    t.index ["general_account_id"], name: "index_cash_allocations_on_general_account_id"
    t.index ["legal_entity_id"], name: "index_cash_allocations_on_legal_entity_id"
    t.index ["team_id"], name: "index_cash_allocations_on_team_id"
    t.check_constraint "amount_cents <> 0", name: "cash_allocations_non_zero"
  end

  create_table "cash_entries", force: :cascade do |t|
    t.datetime "allocated_at"
    t.bigint "amount_cents", null: false
    t.bigint "cash_account_id", null: false
    t.string "communication"
    t.string "counterparty_iban"
    t.string "counterparty_name"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.date "entry_date", null: false
    t.string "excluded_reason"
    t.string "external_ref"
    t.string "label", null: false
    t.string "statement_ref"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.date "value_date"
    t.index ["cash_account_id", "external_ref"], name: "index_cash_entries_on_external_ref", unique: true, where: "(external_ref IS NOT NULL)"
    t.index ["cash_account_id"], name: "index_cash_entries_on_cash_account_id"
    t.index ["deleted_at"], name: "index_cash_entries_on_deleted_at"
    t.index ["entry_date"], name: "index_cash_entries_on_entry_date"
    t.index ["status"], name: "index_cash_entries_on_status"
    t.check_constraint "amount_cents <> 0", name: "cash_entries_non_zero"
  end

  create_table "catalog_items", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "category"
    t.string "channel", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "name", null: false
    t.string "reference"
    t.string "unit", default: "piece", null: false
    t.datetime "updated_at", null: false
    t.index ["channel", "name"], name: "index_catalog_items_on_channel_and_name"
    t.index ["deleted_at"], name: "index_catalog_items_on_deleted_at"
  end

  create_table "catalog_prices", force: :cascade do |t|
    t.date "active_from", null: false
    t.date "active_until"
    t.bigint "catalog_item_id", null: false
    t.datetime "created_at", null: false
    t.integer "member_price_cents", null: false
    t.string "note"
    t.integer "public_price_cents"
    t.integer "purchase_price_cents"
    t.integer "reference_price_cents"
    t.datetime "updated_at", null: false
    t.index ["catalog_item_id", "active_from"], name: "index_catalog_prices_on_catalog_item_id_and_active_from", unique: true
    t.index ["catalog_item_id"], name: "index_catalog_prices_on_catalog_item_id"
  end

  create_table "coda_imports", force: :cascade do |t|
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.date "creation_date"
    t.datetime "deleted_at"
    t.integer "entries_count", default: 0, null: false
    t.string "file_reference"
    t.string "filename", null: false
    t.datetime "imported_at"
    t.text "report"
    t.string "sha256", null: false
    t.integer "statements_count", default: 0, null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.string "whodunnit"
    t.index ["deleted_at"], name: "index_coda_imports_on_deleted_at"
    t.index ["sha256"], name: "index_coda_imports_on_sha256", unique: true
  end

  create_table "coda_statements", force: :cascade do |t|
    t.bigint "cash_account_id", null: false
    t.bigint "coda_import_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.integer "entries_count", default: 0, null: false
    t.bigint "new_balance_cents", null: false
    t.date "new_balance_date"
    t.bigint "old_balance_cents", null: false
    t.date "old_balance_date"
    t.integer "period_year", null: false
    t.string "sequence_number", null: false
    t.datetime "updated_at", null: false
    t.index ["cash_account_id", "period_year", "sequence_number"], name: "index_coda_statements_on_account_and_sequence", unique: true
    t.index ["cash_account_id"], name: "index_coda_statements_on_cash_account_id"
    t.index ["coda_import_id"], name: "index_coda_statements_on_coda_import_id"
    t.index ["deleted_at"], name: "index_coda_statements_on_deleted_at"
  end

  create_table "coworking_packs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.integer "days_total", null: false
    t.datetime "deleted_at"
    t.datetime "expires_at", null: false
    t.datetime "expiry_reminder_sent_at"
    t.string "payment_method", null: false
    t.integer "price_cents", default: 0, null: false
    t.datetime "purchased_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_coworking_packs_on_customer_id"
    t.index ["deleted_at"], name: "index_coworking_packs_on_deleted_at"
    t.index ["expires_at"], name: "index_coworking_packs_on_expires_at"
  end

  create_table "coworking_reservations", force: :cascade do |t|
    t.bigint "coworking_pack_id", null: false
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.date "date", null: false
    t.datetime "deleted_at"
    t.datetime "updated_at", null: false
    t.index ["coworking_pack_id"], name: "index_coworking_reservations_on_coworking_pack_id"
    t.index ["customer_id"], name: "index_coworking_reservations_on_customer_id"
    t.index ["date"], name: "index_coworking_reservations_on_date"
    t.index ["deleted_at"], name: "index_coworking_reservations_on_deleted_at"
  end

  create_table "customers", force: :cascade do |t|
    t.string "address_city"
    t.string "address_country"
    t.string "address_line"
    t.string "address_zip"
    t.datetime "created_at", null: false
    t.string "customer_type", default: "individual", null: false
    t.datetime "deleted_at"
    t.citext "email"
    t.string "first_name"
    t.bigint "human_id"
    t.string "language", default: "fr", null: false
    t.string "last_name"
    t.boolean "marketing_consent", default: false, null: false
    t.boolean "nps_eligible", default: false, null: false
    t.string "organization_name"
    t.string "peppol_id"
    t.string "phone"
    t.string "stripe_customer_id"
    t.datetime "updated_at", null: false
    t.string "vat_number"
    t.index ["customer_type"], name: "index_customers_on_customer_type"
    t.index ["email"], name: "index_customers_on_email_unique_live", unique: true, where: "(deleted_at IS NULL)"
    t.index ["human_id"], name: "index_customers_on_human_id"
  end

  create_table "cycle_actions", force: :cascade do |t|
    t.datetime "archived_at"
    t.integer "category", default: 0, null: false
    t.boolean "completed", default: false
    t.datetime "created_at", null: false
    t.bigint "delegate_to_human_id"
    t.datetime "deleted_at"
    t.decimal "hours", precision: 5, scale: 2
    t.bigint "human_id", null: false
    t.string "label", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_cycle_actions_on_category"
    t.index ["completed"], name: "index_cycle_actions_on_completed"
    t.index ["delegate_to_human_id"], name: "index_cycle_actions_on_delegate_to_human_id"
    t.index ["human_id", "archived_at"], name: "index_cycle_actions_on_human_id_and_archived_at"
    t.index ["human_id", "category", "position"], name: "index_cycle_actions_on_human_id_and_category_and_position"
    t.index ["human_id"], name: "index_cycle_actions_on_human_id"
  end

  create_table "cycles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.date "end_date", null: false
    t.string "name", null: false
    t.date "start_date", null: false
    t.datetime "updated_at", null: false
    t.index ["start_date", "end_date"], name: "index_cycles_on_start_date_and_end_date"
  end

  create_table "decisions", force: :cascade do |t|
    t.bigint "agenda_item_id"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "gathering_id"
    t.bigint "recorded_by_id", null: false
    t.string "summary", null: false
    t.date "taken_at", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["agenda_item_id"], name: "index_decisions_on_agenda_item_id"
    t.index ["gathering_id"], name: "index_decisions_on_gathering_id"
    t.index ["recorded_by_id"], name: "index_decisions_on_recorded_by_id"
    t.index ["taken_at"], name: "index_decisions_on_taken_at", order: :desc
  end

  create_table "event_categories", force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.datetime "deleted_at", precision: nil
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "events", force: :cascade do |t|
    t.integer "attendees"
    t.datetime "created_at", null: false
    t.datetime "deleted_at", precision: nil
    t.datetime "ends_at"
    t.bigint "event_category_id", null: false
    t.string "name"
    t.text "notes"
    t.integer "sales_amount_cents"
    t.datetime "starts_at"
    t.string "status"
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["event_category_id"], name: "index_events_on_event_category_id"
  end

  create_table "experience_availabilities", force: :cascade do |t|
    t.date "available_on"
    t.datetime "created_at", null: false
    t.integer "duration_minutes"
    t.bigint "experience_id", null: false
    t.integer "max_participants"
    t.string "notes"
    t.string "starts_at"
    t.datetime "updated_at", null: false
    t.index ["experience_id"], name: "index_experience_availabilities_on_experience_id"
  end

  create_table "experience_bookings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "experience_availability_id", null: false
    t.text "notes"
    t.integer "participants"
    t.text "refusal_reason"
    t.string "status"
    t.bigint "stay_id", null: false
    t.datetime "updated_at", null: false
    t.index ["experience_availability_id"], name: "index_experience_bookings_on_experience_availability_id"
    t.index ["stay_id"], name: "index_experience_bookings_on_stay_id"
  end

  create_table "experiences", force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.datetime "deleted_at", precision: nil
    t.text "description"
    t.string "duration"
    t.decimal "duration_hours", precision: 4, scale: 2
    t.integer "fixed_price_cents", default: 0
    t.bigint "human_id"
    t.integer "max_participants"
    t.integer "min_participants"
    t.string "name"
    t.string "photo"
    t.integer "price_cents"
    t.string "summary"
    t.datetime "updated_at", null: false
    t.index ["human_id"], name: "index_experiences_on_human_id"
  end

  create_table "fiscal_years", force: :cascade do |t|
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.date "ends_on", null: false
    t.bigint "legal_entity_id", null: false
    t.date "starts_on", null: false
    t.string "status", default: "open", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_fiscal_years_on_deleted_at"
    t.index ["legal_entity_id", "starts_on"], name: "index_fiscal_years_on_legal_entity_id_and_starts_on", unique: true
    t.index ["legal_entity_id"], name: "index_fiscal_years_on_legal_entity_id"
  end

  create_table "gathering_action_humans", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "gathering_action_id", null: false
    t.bigint "human_id", null: false
    t.datetime "updated_at", null: false
    t.index ["gathering_action_id", "human_id"], name: "index_gathering_action_humans_uniqueness", unique: true
    t.index ["gathering_action_id"], name: "index_gathering_action_humans_on_gathering_action_id"
    t.index ["human_id"], name: "index_gathering_action_humans_on_human_id"
  end

  create_table "gathering_actions", force: :cascade do |t|
    t.boolean "completed", default: false, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "gathering_id", null: false
    t.string "label", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_gathering_actions_on_deleted_at"
    t.index ["gathering_id", "position"], name: "index_gathering_actions_on_gathering_id_and_position"
    t.index ["gathering_id"], name: "index_gathering_actions_on_gathering_id"
  end

  create_table "gathering_categories", force: :cascade do |t|
    t.string "color", null: false
    t.datetime "created_at", null: false
    t.integer "default_duration_minutes"
    t.time "default_start_time"
    t.datetime "deleted_at"
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "gatherings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.datetime "ends_at", null: false
    t.bigint "gathering_category_id", null: false
    t.string "location"
    t.string "name"
    t.datetime "starts_at", null: false
    t.datetime "updated_at", null: false
    t.index ["gathering_category_id"], name: "index_gatherings_on_gathering_category_id"
    t.index ["starts_at", "ends_at"], name: "index_gatherings_on_starts_at_and_ends_at"
  end

  create_table "general_accounts", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.integer "klass", null: false
    t.string "name", null: false
    t.string "nature", null: false
    t.boolean "reconcilable", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_general_accounts_on_code", unique: true
    t.index ["deleted_at"], name: "index_general_accounts_on_deleted_at"
    t.index ["klass"], name: "index_general_accounts_on_klass"
  end

  create_table "hamac_bookings", force: :cascade do |t|
    t.integer "count", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "email"
    t.string "firstname"
    t.date "from_date"
    t.string "group_name"
    t.string "kind", default: "simple", null: false
    t.string "lastname"
    t.text "notes"
    t.string "phone"
    t.integer "price_cents"
    t.string "status"
    t.date "to_date"
    t.string "token"
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_hamac_bookings_on_deleted_at"
    t.index ["from_date", "to_date"], name: "index_hamac_bookings_on_from_date_and_to_date"
    t.index ["token"], name: "index_hamac_bookings_on_token", unique: true
  end

  create_table "household_members", force: :cascade do |t|
    t.date "born_on"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.date "ended_on"
    t.bigint "household_id", null: false
    t.bigint "human_id"
    t.string "kind", default: "adult", null: false
    t.string "name", null: false
    t.date "started_on", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_household_members_on_deleted_at"
    t.index ["household_id", "started_on"], name: "index_household_members_on_household_id_and_started_on"
    t.index ["household_id"], name: "index_household_members_on_household_id"
    t.index ["human_id"], name: "index_household_members_on_human_id"
  end

  create_table "households", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "kind", default: "resident", null: false
    t.date "moved_in_on"
    t.date "moved_out_on"
    t.string "name", null: false
    t.text "notes"
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_households_on_deleted_at"
  end

  create_table "human_roles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date"
    t.bigint "human_id", null: false
    t.bigint "role_id", null: false
    t.integer "status", default: 1, null: false
    t.datetime "updated_at", null: false
    t.index ["human_id"], name: "index_human_roles_on_human_id"
    t.index ["role_id"], name: "index_human_roles_on_role_id"
  end

  create_table "humans", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "cycle_active", default: false
    t.datetime "deleted_at", precision: nil
    t.text "description"
    t.string "email"
    t.string "name"
    t.string "photo"
    t.boolean "roles_enabled", default: true, null: false
    t.string "status", default: "active"
    t.string "summary"
    t.datetime "updated_at", null: false
  end

  create_table "humans_tasks", id: false, force: :cascade do |t|
    t.bigint "human_id", null: false
    t.bigint "task_id", null: false
    t.index ["human_id", "task_id"], name: "index_humans_tasks_on_human_id_and_task_id"
    t.index ["task_id", "human_id"], name: "index_humans_tasks_on_task_id_and_human_id"
  end

  create_table "journal_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.date "entry_date", null: false
    t.bigint "fiscal_year_id", null: false
    t.string "journal", null: false
    t.string "label", null: false
    t.bigint "legal_entity_id", null: false
    t.datetime "locked_at"
    t.integer "number", null: false
    t.datetime "posted_at", null: false
    t.bigint "reversal_of_id"
    t.bigint "source_id"
    t.string "source_type"
    t.datetime "updated_at", null: false
    t.string "whodunnit"
    t.index ["deleted_at"], name: "index_journal_entries_on_deleted_at"
    t.index ["entry_date"], name: "index_journal_entries_on_entry_date"
    t.index ["fiscal_year_id", "journal", "number"], name: "index_journal_entries_on_sequence", unique: true
    t.index ["fiscal_year_id"], name: "index_journal_entries_on_fiscal_year_id"
    t.index ["legal_entity_id"], name: "index_journal_entries_on_legal_entity_id"
    t.index ["reversal_of_id"], name: "index_journal_entries_on_single_reversal", unique: true, where: "(reversal_of_id IS NOT NULL)"
    t.index ["source_type", "source_id", "journal"], name: "index_journal_entries_on_source", unique: true, where: "(source_id IS NOT NULL)"
  end

  create_table "journal_lines", force: :cascade do |t|
    t.bigint "analytic_account_id"
    t.datetime "created_at", null: false
    t.bigint "credit_cents", default: 0, null: false
    t.bigint "debit_cents", default: 0, null: false
    t.datetime "deleted_at"
    t.bigint "general_account_id", null: false
    t.bigint "journal_entry_id", null: false
    t.string "label"
    t.bigint "team_id"
    t.datetime "updated_at", null: false
    t.index ["analytic_account_id"], name: "index_journal_lines_on_analytic_account_id"
    t.index ["deleted_at"], name: "index_journal_lines_on_deleted_at"
    t.index ["general_account_id"], name: "index_journal_lines_on_general_account_id"
    t.index ["journal_entry_id"], name: "index_journal_lines_on_journal_entry_id"
    t.index ["team_id"], name: "index_journal_lines_on_team_id"
    t.check_constraint "debit_cents >= 0 AND credit_cents >= 0 AND (debit_cents = 0 OR credit_cents = 0) AND (debit_cents > 0 OR credit_cents > 0)", name: "journal_lines_one_side_only"
  end

  create_table "legal_entities", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "form", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.string "vat_number"
    t.string "vat_regime", default: "exempt", null: false
    t.index ["deleted_at"], name: "index_legal_entities_on_deleted_at"
    t.index ["name"], name: "index_legal_entities_on_name", unique: true
  end

  create_table "lodging_compositions", force: :cascade do |t|
    t.bigint "component_lodging_id", null: false
    t.bigint "composite_lodging_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["component_lodging_id"], name: "index_lodging_compositions_on_component_lodging_id"
    t.index ["composite_lodging_id", "component_lodging_id"], name: "index_lodging_compositions_unique_pair", unique: true
    t.index ["composite_lodging_id"], name: "index_lodging_compositions_on_composite_lodging_id"
  end

  create_table "lodging_rooms", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "lodging_id", null: false
    t.bigint "room_id", null: false
    t.datetime "updated_at", null: false
    t.index ["lodging_id"], name: "index_lodging_rooms_on_lodging_id"
    t.index ["room_id"], name: "index_lodging_rooms_on_room_id"
  end

  create_table "lodgings", force: :cascade do |t|
    t.boolean "available_for_bookings"
    t.datetime "created_at", null: false
    t.datetime "deleted_at", precision: nil
    t.text "description"
    t.string "name"
    t.boolean "party_hall_availability"
    t.integer "price_night_cents", default: 0, null: false
    t.boolean "show_on_reports", default: true
    t.string "summary"
    t.datetime "updated_at", null: false
    t.integer "weekend_discount_cents", default: 0, null: false
  end

  create_table "meal_orders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date"
    t.datetime "deleted_at"
    t.string "kind"
    t.integer "people", default: 1, null: false
    t.integer "price_cents"
    t.bigint "stay_id", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_meal_orders_on_deleted_at"
    t.index ["stay_id"], name: "index_meal_orders_on_stay_id"
  end

  create_table "member_accounts", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "code", null: false
    t.string "contact_email"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "household_id"
    t.bigint "human_id"
    t.string "kind", null: false
    t.string "name", null: false
    t.bigint "opening_balance_cents", default: 0, null: false
    t.date "opening_balance_on"
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_member_accounts_on_code", unique: true
    t.index ["deleted_at"], name: "index_member_accounts_on_deleted_at"
    t.index ["household_id"], name: "index_member_accounts_on_household_id"
    t.index ["human_id"], name: "index_member_accounts_on_human_id"
    t.check_constraint "kind::text = 'household'::text AND household_id IS NOT NULL AND human_id IS NULL OR kind::text = 'human'::text AND human_id IS NOT NULL AND household_id IS NULL OR kind::text = 'entity'::text AND household_id IS NULL AND human_id IS NULL", name: "member_accounts_anchor_check"
  end

  create_table "notes", force: :cascade do |t|
    t.text "body"
    t.string "color"
    t.datetime "created_at", null: false
    t.date "date"
    t.datetime "deleted_at", precision: nil
    t.datetime "updated_at", null: false
  end

  create_table "paper_sheets", force: :cascade do |t|
    t.string "channel", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.datetime "encoded_at"
    t.bigint "encoded_by_id"
    t.string "entry_mode", default: "quantity", null: false
    t.bigint "member_account_id"
    t.text "notes"
    t.date "period_month", null: false
    t.string "status", default: "open", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_paper_sheets_on_deleted_at"
    t.index ["encoded_by_id"], name: "index_paper_sheets_on_encoded_by_id"
    t.index ["member_account_id"], name: "index_paper_sheets_on_member_account_id"
    t.index ["period_month", "channel"], name: "index_paper_sheets_on_period_month_and_channel"
  end

  create_table "payment_versions", force: :cascade do |t|
    t.datetime "created_at"
    t.string "event", null: false
    t.uuid "item_id", null: false
    t.string "item_type", null: false
    t.text "object"
    t.text "object_changes"
    t.string "whodunnit"
    t.index ["item_type", "item_id"], name: "index_payment_versions_on_item_type_and_item_id"
  end

  create_table "payments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "amount_cents", default: 0, null: false
    t.bigint "booking_id"
    t.bigint "coworking_pack_id"
    t.datetime "created_at", null: false
    t.datetime "deleted_at", precision: nil
    t.string "payment_method"
    t.bigint "space_booking_id"
    t.string "status"
    t.bigint "stay_id"
    t.string "stripe_checkout_session_id"
    t.string "stripe_payment_intent_id"
    t.datetime "updated_at", null: false
    t.index ["booking_id"], name: "index_payments_on_booking_id"
    t.index ["coworking_pack_id"], name: "index_payments_on_coworking_pack_id"
    t.index ["id"], name: "index_payments_on_id", unique: true
    t.index ["space_booking_id"], name: "index_payments_on_space_booking_id"
    t.index ["stay_id"], name: "index_payments_on_stay_id"
  end

  create_table "portal_otps", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.string "code_digest", null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.citext "email", null: false
    t.datetime "expires_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email", "created_at"], name: "index_portal_otps_on_email_and_created_at"
  end

  create_table "products", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at", precision: nil
    t.text "description"
    t.string "name"
    t.string "photo"
    t.integer "price_cents"
    t.integer "stock"
    t.datetime "updated_at", null: false
  end

  create_table "projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at", precision: nil
    t.text "description"
    t.date "due_date"
    t.bigint "human_id", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["human_id"], name: "index_projects_on_human_id"
  end

  create_table "rate_versions", force: :cascade do |t|
    t.date "active_from", null: false
    t.date "active_until"
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.string "note"
    t.bigint "rate_id", null: false
    t.datetime "updated_at", null: false
    t.index ["rate_id", "active_from"], name: "index_rate_versions_on_rate_id_and_active_from", unique: true
    t.index ["rate_id"], name: "index_rate_versions_on_rate_id"
  end

  create_table "rates", force: :cascade do |t|
    t.integer "amount_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.string "label"
    t.string "unit", default: "cents", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_rates_on_key", unique: true
  end

  create_table "recurring_charges", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "amount_cents"
    t.string "applies_to", default: "account", null: false
    t.string "basis", default: "flat", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.date "ends_on"
    t.string "flow"
    t.bigint "household_member_id"
    t.string "kind"
    t.string "label", null: false
    t.bigint "member_account_id"
    t.string "rate_key"
    t.string "split_label"
    t.string "split_rate_key"
    t.date "starts_on", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_recurring_charges_on_deleted_at"
    t.index ["household_member_id"], name: "index_recurring_charges_on_household_member_id"
    t.index ["member_account_id"], name: "index_recurring_charges_on_member_account_id"
    t.check_constraint "amount_cents IS NOT NULL AND rate_key IS NULL OR amount_cents IS NULL AND rate_key IS NOT NULL", name: "recurring_charges_amount_source_check"
    t.check_constraint "applies_to::text = 'account'::text AND member_account_id IS NOT NULL OR applies_to::text <> 'account'::text AND member_account_id IS NULL", name: "recurring_charges_scope_check"
  end

  create_table "rental_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.string "name"
    t.string "photo"
    t.integer "price_cents"
    t.integer "stock"
    t.datetime "updated_at", null: false
  end

  create_table "reservations", force: :cascade do |t|
    t.bigint "booking_id", null: false
    t.datetime "created_at", null: false
    t.date "date"
    t.datetime "deleted_at", precision: nil
    t.bigint "room_id", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_id"], name: "index_reservations_on_booking_id"
    t.index ["room_id"], name: "index_reservations_on_room_id"
  end

  create_table "roles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "name"
    t.jsonb "role_team", default: []
    t.datetime "updated_at", null: false
    t.index ["role_team"], name: "index_roles_on_role_team", using: :gin
  end

  create_table "rooms", force: :cascade do |t|
    t.string "code"
    t.datetime "created_at", null: false
    t.datetime "deleted_at", precision: nil
    t.text "description"
    t.integer "level"
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "sent_emails", force: :cascade do |t|
    t.text "body_html"
    t.text "body_text"
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.string "mailer"
    t.string "postmark_message_id"
    t.datetime "sent_at", null: false
    t.string "source", default: "app", null: false
    t.string "subject"
    t.string "tag"
    t.citext "to_email", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "sent_at"], name: "index_sent_emails_on_customer_id_and_sent_at"
    t.index ["customer_id"], name: "index_sent_emails_on_customer_id"
    t.index ["postmark_message_id"], name: "index_sent_emails_on_postmark_message_id", unique: true, where: "(postmark_message_id IS NOT NULL)"
  end

  create_table "services", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at", precision: nil
    t.text "description"
    t.bigint "human_id"
    t.string "name"
    t.string "photo"
    t.integer "price_cents"
    t.string "summary"
    t.datetime "updated_at", null: false
    t.index ["human_id"], name: "index_services_on_human_id"
  end

  create_table "settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.string "value"
    t.index ["key"], name: "index_settings_on_key", unique: true
  end

  create_table "space_bookings", force: :cascade do |t|
    t.integer "advance_amount_cents"
    t.string "arrival_time"
    t.string "contract_status"
    t.datetime "created_at", null: false
    t.datetime "deleted_at", precision: nil
    t.string "departure_time"
    t.integer "deposit_amount_cents"
    t.string "email"
    t.bigint "event_id"
    t.string "firstname"
    t.date "from_date"
    t.string "group_name"
    t.string "invoice_status"
    t.string "lastname"
    t.text "notes"
    t.boolean "option_beamer", default: false
    t.boolean "option_kitchenware", default: false
    t.boolean "option_tables", default: false
    t.boolean "option_wifi", default: false
    t.integer "paid_amount_cents"
    t.string "payment_method"
    t.string "payment_status"
    t.string "persons"
    t.string "phone"
    t.integer "price_cents"
    t.text "public_notes"
    t.string "status"
    t.string "tier"
    t.date "to_date"
    t.string "token"
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_space_bookings_on_event_id"
  end

  create_table "space_reservations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date"
    t.datetime "deleted_at", precision: nil
    t.string "duration"
    t.bigint "space_booking_id", null: false
    t.bigint "space_id", null: false
    t.datetime "updated_at", null: false
    t.index ["space_booking_id"], name: "index_space_reservations_on_space_booking_id"
    t.index ["space_id"], name: "index_space_reservations_on_space_id"
  end

  create_table "spaces", force: :cascade do |t|
    t.integer "capacity", default: 1, null: false
    t.string "code"
    t.datetime "created_at", null: false
    t.datetime "deleted_at", precision: nil
    t.text "description"
    t.string "name"
    t.integer "position", default: 999
    t.datetime "updated_at", null: false
  end

  create_table "stay_change_requests", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.integer "delta_cents", default: 0, null: false
    t.jsonb "draft_snapshot", default: {}, null: false
    t.integer "new_total_cents", default: 0, null: false
    t.string "refund_iban"
    t.text "refusal_reason"
    t.string "status", default: "pending", null: false
    t.bigint "stay_id", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_stay_change_requests_on_deleted_at"
    t.index ["stay_id", "status"], name: "index_stay_change_requests_on_stay_id_and_status"
    t.index ["stay_id"], name: "index_stay_change_requests_on_stay_id"
  end

  create_table "stay_items", force: :cascade do |t|
    t.bigint "bookable_id", null: false
    t.string "bookable_type", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "stay_id", null: false
    t.datetime "updated_at", null: false
    t.index ["bookable_type", "bookable_id"], name: "index_stay_items_on_bookable_type_and_bookable_id"
    t.index ["stay_id", "bookable_type", "bookable_id"], name: "index_stay_items_on_stay_and_bookable_unique_live", unique: true, where: "(deleted_at IS NULL)"
    t.index ["stay_id"], name: "index_stay_items_on_stay_id"
  end

  create_table "stays", force: :cascade do |t|
    t.datetime "activity_email_sent_at"
    t.string "activity_selection_token"
    t.date "arrival_date"
    t.string "arrival_time"
    t.datetime "balance_reminder_sent_at"
    t.string "category"
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.datetime "deleted_at"
    t.date "departure_date"
    t.string "departure_time"
    t.string "legacy_origin"
    t.text "notes"
    t.string "payment_status", default: "pending", null: false
    t.integer "price_override_cents"
    t.string "source", default: "reservation", null: false
    t.string "status"
    t.string "token"
    t.integer "total_amount_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["activity_selection_token"], name: "index_stays_on_activity_selection_token"
    t.index ["customer_id"], name: "index_stays_on_customer_id"
    t.index ["legacy_origin"], name: "index_stays_on_legacy_origin_unique_live", unique: true, where: "((legacy_origin IS NOT NULL) AND (deleted_at IS NULL))"
    t.index ["source"], name: "index_stays_on_source"
    t.index ["token"], name: "index_stays_on_token", unique: true
  end

  create_table "stripe_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_type"
    t.string "object_id"
    t.datetime "updated_at", null: false
    t.string "webhook_id"
  end

  create_table "subscriptions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.boolean "newsletter"
    t.datetime "updated_at", null: false
  end

  create_table "tasks", force: :cascade do |t|
    t.bigint "bundle_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at", precision: nil
    t.text "description"
    t.date "due_date"
    t.string "name"
    t.bigint "project_id", null: false
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["bundle_id"], name: "index_tasks_on_bundle_id"
    t.index ["project_id"], name: "index_tasks_on_project_id"
  end

  create_table "team_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "human_id", null: false
    t.string "role", default: "member", null: false
    t.bigint "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_team_memberships_on_deleted_at"
    t.index ["human_id"], name: "index_team_memberships_on_human_id"
    t.index ["team_id", "human_id"], name: "index_team_memberships_on_team_id_and_human_id", unique: true
    t.index ["team_id"], name: "index_team_memberships_on_team_id"
  end

  create_table "teams", force: :cascade do |t|
    t.string "analytic_code"
    t.datetime "created_at", null: false
    t.datetime "deleted_at", precision: nil
    t.text "description"
    t.string "kind"
    t.string "name"
    t.bigint "parent_id"
    t.datetime "updated_at", null: false
    t.index ["analytic_code"], name: "index_teams_on_analytic_code", unique: true
    t.index ["parent_id"], name: "index_teams_on_parent_id"
  end

  create_table "unavailabilities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date"
    t.bigint "lodging_id", null: false
    t.datetime "updated_at", null: false
    t.index ["lodging_id"], name: "index_unavailabilities_on_lodging_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.bigint "human_id"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.boolean "restricted_to_experiences", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["human_id"], name: "index_users_on_human_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "van_bookings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "email"
    t.string "firstname"
    t.date "from_date"
    t.string "group_name"
    t.string "lastname"
    t.text "notes"
    t.string "phone"
    t.integer "price_cents"
    t.string "status"
    t.date "to_date"
    t.string "token"
    t.datetime "updated_at", null: false
    t.integer "vehicles", default: 1, null: false
    t.index ["deleted_at"], name: "index_van_bookings_on_deleted_at"
    t.index ["from_date", "to_date"], name: "index_van_bookings_on_from_date_and_to_date"
  end

  create_table "versions", force: :cascade do |t|
    t.datetime "created_at"
    t.string "event", null: false
    t.bigint "item_id", null: false
    t.string "item_type", null: false
    t.text "object"
    t.text "object_changes"
    t.string "whodunnit"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  create_table "watchman_notes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date"
    t.text "note"
    t.datetime "updated_at", null: false
    t.index ["date"], name: "index_watchman_notes_on_date"
  end

  add_foreign_key "account_entries", "account_entries", column: "reversal_of_id"
  add_foreign_key "account_entries", "account_statements"
  add_foreign_key "account_entries", "catalog_items"
  add_foreign_key "account_entries", "member_accounts"
  add_foreign_key "account_entries", "paper_sheets"
  add_foreign_key "account_settlements", "account_entries"
  add_foreign_key "account_settlements", "member_accounts"
  add_foreign_key "account_statements", "member_accounts"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agenda_items", "gatherings"
  add_foreign_key "agenda_items", "humans", column: "author_id"
  add_foreign_key "agenda_items", "humans", column: "carrier_id"
  add_foreign_key "analytic_accounts", "teams"
  add_foreign_key "booking_page_views", "bookings"
  add_foreign_key "bookings", "lodgings"
  add_foreign_key "bundles", "projects"
  add_foreign_key "bundles", "teams"
  add_foreign_key "cash_accounts", "general_accounts"
  add_foreign_key "cash_accounts", "legal_entities"
  add_foreign_key "cash_allocations", "analytic_accounts"
  add_foreign_key "cash_allocations", "cash_entries"
  add_foreign_key "cash_allocations", "general_accounts"
  add_foreign_key "cash_allocations", "legal_entities"
  add_foreign_key "cash_allocations", "teams"
  add_foreign_key "cash_entries", "cash_accounts"
  add_foreign_key "catalog_prices", "catalog_items"
  add_foreign_key "coda_statements", "cash_accounts"
  add_foreign_key "coda_statements", "coda_imports"
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
  add_foreign_key "fiscal_years", "legal_entities"
  add_foreign_key "gathering_action_humans", "gathering_actions"
  add_foreign_key "gathering_action_humans", "humans"
  add_foreign_key "gathering_actions", "gatherings"
  add_foreign_key "gatherings", "gathering_categories"
  add_foreign_key "household_members", "households"
  add_foreign_key "household_members", "humans"
  add_foreign_key "human_roles", "humans"
  add_foreign_key "human_roles", "roles"
  add_foreign_key "journal_entries", "fiscal_years"
  add_foreign_key "journal_entries", "journal_entries", column: "reversal_of_id"
  add_foreign_key "journal_entries", "legal_entities"
  add_foreign_key "journal_lines", "analytic_accounts"
  add_foreign_key "journal_lines", "general_accounts"
  add_foreign_key "journal_lines", "journal_entries"
  add_foreign_key "journal_lines", "teams"
  add_foreign_key "lodging_compositions", "lodgings", column: "component_lodging_id"
  add_foreign_key "lodging_compositions", "lodgings", column: "composite_lodging_id"
  add_foreign_key "lodging_rooms", "lodgings"
  add_foreign_key "lodging_rooms", "rooms"
  add_foreign_key "meal_orders", "stays"
  add_foreign_key "member_accounts", "households"
  add_foreign_key "member_accounts", "humans"
  add_foreign_key "paper_sheets", "member_accounts"
  add_foreign_key "paper_sheets", "users", column: "encoded_by_id"
  add_foreign_key "payments", "bookings"
  add_foreign_key "payments", "coworking_packs"
  add_foreign_key "payments", "space_bookings"
  add_foreign_key "payments", "stays"
  add_foreign_key "projects", "humans"
  add_foreign_key "rate_versions", "rates"
  add_foreign_key "recurring_charges", "household_members"
  add_foreign_key "recurring_charges", "member_accounts"
  add_foreign_key "reservations", "bookings"
  add_foreign_key "reservations", "rooms"
  add_foreign_key "sent_emails", "customers"
  add_foreign_key "services", "humans"
  add_foreign_key "space_bookings", "events"
  add_foreign_key "space_reservations", "space_bookings"
  add_foreign_key "space_reservations", "spaces"
  add_foreign_key "stay_change_requests", "stays"
  add_foreign_key "stay_items", "stays"
  add_foreign_key "stays", "customers"
  add_foreign_key "tasks", "bundles"
  add_foreign_key "tasks", "projects"
  add_foreign_key "team_memberships", "humans"
  add_foreign_key "team_memberships", "teams"
  add_foreign_key "teams", "teams", column: "parent_id"
  add_foreign_key "unavailabilities", "lodgings"
  add_foreign_key "users", "humans"
end
