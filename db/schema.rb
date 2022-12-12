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

ActiveRecord::Schema[7.0].define(version: 2022_12_10_175157) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

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
    t.boolean "invoice_status"
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
    t.index ["lodging_id"], name: "index_bookings_on_lodging_id"
  end

  create_table "event_categories", force: :cascade do |t|
    t.string "name"
    t.string "color"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "events", force: :cascade do |t|
    t.string "name"
    t.bigint "event_category_id", null: false
    t.datetime "starts_at"
    t.datetime "ends_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_category_id"], name: "index_events_on_event_category_id"
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
    t.integer "price_weekend_cents", default: 0, null: false
    t.boolean "party_hall_availability"
  end

  create_table "reservations", force: :cascade do |t|
    t.bigint "booking_id", null: false
    t.bigint "room_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "date"
    t.index ["booking_id"], name: "index_reservations_on_booking_id"
    t.index ["room_id"], name: "index_reservations_on_room_id"
  end

  create_table "rooms", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "level"
  end

  add_foreign_key "bookings", "lodgings"
  add_foreign_key "events", "event_categories"
  add_foreign_key "lodging_rooms", "lodgings"
  add_foreign_key "lodging_rooms", "rooms"
  add_foreign_key "reservations", "bookings"
  add_foreign_key "reservations", "rooms"
end
