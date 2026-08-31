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

ActiveRecord::Schema[8.1].define(version: 2026_08_31_102000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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

  create_table "advertising_order_line_days", force: :cascade do |t|
    t.bigint "advertising_order_line_id", null: false
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.integer "shows", null: false
    t.datetime "updated_at", null: false
    t.index ["advertising_order_line_id", "date"], name: "index_advertising_order_line_days_on_line_and_date", unique: true
    t.index ["advertising_order_line_id"], name: "index_advertising_order_line_days_on_advertising_order_line_id"
    t.check_constraint "shows > 0", name: "advertising_order_line_days_shows_positive"
  end

  create_table "advertising_order_lines", force: :cascade do |t|
    t.bigint "advertising_order_id", null: false
    t.bigint "broadcast_point_group_id", null: false
    t.datetime "created_at", null: false
    t.integer "price_per_day_cents", null: false
    t.integer "total_shows", default: 0, null: false
    t.integer "total_sum_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["advertising_order_id", "broadcast_point_group_id"], name: "index_advertising_order_lines_on_order_and_group", unique: true
    t.index ["advertising_order_id"], name: "index_advertising_order_lines_on_advertising_order_id"
    t.index ["broadcast_point_group_id"], name: "index_advertising_order_lines_on_broadcast_point_group_id"
    t.check_constraint "price_per_day_cents >= 0", name: "advertising_order_lines_price_per_day_cents_non_negative"
    t.check_constraint "total_shows >= 0", name: "advertising_order_lines_total_shows_non_negative"
    t.check_constraint "total_sum_cents >= 0", name: "advertising_order_lines_total_sum_cents_non_negative"
  end

  create_table "advertising_orders", force: :cascade do |t|
    t.string "business_sphere"
    t.string "clip_title"
    t.integer "coefficient_percent", default: 0, null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_user_id", null: false
    t.integer "discount_cents", default: 0, null: false
    t.integer "document_version", default: 1, null: false
    t.integer "duration_seconds"
    t.bigint "media_asset_id", null: false
    t.bigint "organization_id", null: false
    t.string "placement_kind", default: "own_atmosphere", null: false
    t.string "product_name", null: false
    t.bigint "rotation_id", null: false
    t.string "status", default: "draft", null: false
    t.integer "total_shows", default: 0, null: false
    t.integer "total_sum_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_user_id"], name: "index_advertising_orders_on_created_by_user_id"
    t.index ["media_asset_id"], name: "index_advertising_orders_on_media_asset_id"
    t.index ["organization_id"], name: "index_advertising_orders_on_organization_id"
    t.index ["rotation_id"], name: "index_advertising_orders_on_rotation_id", unique: true
    t.index ["status"], name: "index_advertising_orders_on_status"
    t.check_constraint "discount_cents >= 0", name: "advertising_orders_discount_cents_non_negative"
    t.check_constraint "total_shows >= 0", name: "advertising_orders_total_shows_non_negative"
    t.check_constraint "total_sum_cents >= 0", name: "advertising_orders_total_sum_cents_non_negative"
  end

  create_table "airtime_bookings", force: :cascade do |t|
    t.bigint "broadcast_point_group_id", null: false
    t.datetime "created_at", null: false
    t.datetime "ends_at", null: false
    t.bigint "organization_id", null: false
    t.integer "seconds", null: false
    t.datetime "starts_at", null: false
    t.string "status", default: "confirmed", null: false
    t.datetime "updated_at", null: false
    t.index ["broadcast_point_group_id"], name: "index_airtime_bookings_on_broadcast_point_group_id"
    t.index ["organization_id", "starts_at", "ends_at"], name: "idx_on_organization_id_starts_at_ends_at_f3b48d3772"
    t.index ["organization_id"], name: "index_airtime_bookings_on_organization_id"
    t.index ["status"], name: "index_airtime_bookings_on_status"
    t.check_constraint "ends_at > starts_at", name: "airtime_bookings_ends_after_starts"
    t.check_constraint "seconds > 0", name: "airtime_bookings_seconds_positive"
  end

  create_table "broadcast_point_group_memberships", force: :cascade do |t|
    t.bigint "broadcast_point_group_id", null: false
    t.datetime "created_at", null: false
    t.bigint "screen_id", null: false
    t.datetime "updated_at", null: false
    t.index ["broadcast_point_group_id", "screen_id"], name: "index_broadcast_point_group_memberships_unique", unique: true
    t.index ["broadcast_point_group_id"], name: "idx_on_broadcast_point_group_id_7614dd11c4"
    t.index ["screen_id"], name: "index_broadcast_point_group_memberships_on_screen_id"
  end

  create_table "broadcast_point_groups", force: :cascade do |t|
    t.integer "commercial_quota_percent"
    t.string "commercial_quota_period"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "name"], name: "index_broadcast_point_groups_on_organization_id_and_name", unique: true
    t.index ["organization_id"], name: "index_broadcast_point_groups_on_organization_id"
  end

  create_table "directory_business_spheres", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index "lower((name)::text)", name: "index_directory_business_spheres_on_lower_name", unique: true
  end

  create_table "locations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.jsonb "operating_hours", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_locations_on_name", unique: true
  end

  create_table "media_assets", force: :cascade do |t|
    t.string "content_kind", null: false
    t.string "content_type", null: false
    t.datetime "created_at", null: false
    t.integer "duration_seconds"
    t.jsonb "metadata", default: {}, null: false
    t.bigint "organization_id", null: false
    t.string "processing_status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "uploaded_by_id"
    t.string "visibility", null: false
    t.index ["content_type"], name: "index_media_assets_on_content_type"
    t.index ["organization_id", "created_at"], name: "index_media_assets_on_organization_id_and_created_at", order: { created_at: :desc }
    t.index ["organization_id", "processing_status"], name: "index_media_assets_on_organization_id_and_processing_status"
    t.index ["organization_id"], name: "index_media_assets_on_organization_id"
    t.index ["uploaded_by_id"], name: "index_media_assets_on_uploaded_by_id"
    t.index ["visibility"], name: "index_media_assets_on_visibility"
  end

  create_table "media_plans", force: :cascade do |t|
    t.bigint "advertising_order_line_id"
    t.bigint "airtime_booking_id", null: false
    t.bigint "broadcast_point_group_id", null: false
    t.datetime "created_at", null: false
    t.datetime "ends_at", null: false
    t.bigint "organization_id", null: false
    t.string "placement_kind", default: "own_atmosphere", null: false
    t.bigint "rotation_id", null: false
    t.integer "shows_per_hour"
    t.datetime "starts_at", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["advertising_order_line_id"], name: "index_media_plans_on_advertising_order_line_id"
    t.index ["airtime_booking_id"], name: "index_media_plans_on_airtime_booking_id"
    t.index ["broadcast_point_group_id"], name: "index_media_plans_on_broadcast_point_group_id"
    t.index ["organization_id", "starts_at", "ends_at"], name: "index_media_plans_on_organization_id_and_starts_at_and_ends_at"
    t.index ["organization_id"], name: "index_media_plans_on_organization_id"
    t.index ["placement_kind"], name: "index_media_plans_on_placement_kind"
    t.index ["rotation_id"], name: "index_media_plans_on_rotation_id"
    t.index ["status"], name: "index_media_plans_on_status"
  end

  create_table "organizations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", default: "client", null: false
    t.string "name", null: false
    t.string "time_zone", default: "UTC", null: false
    t.datetime "updated_at", null: false
    t.index ["kind"], name: "index_organizations_one_operator", unique: true, where: "((kind)::text = 'operator'::text)"
  end

  create_table "play_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "media_asset_id", null: false
    t.bigint "organization_id", null: false
    t.bigint "screen_id", null: false
    t.string "source", default: "agent", null: false
    t.datetime "started_at", null: false
    t.datetime "updated_at", null: false
    t.index ["media_asset_id"], name: "index_play_logs_on_media_asset_id"
    t.index ["organization_id", "started_at"], name: "index_play_logs_on_organization_id_and_started_at"
    t.index ["organization_id"], name: "index_play_logs_on_organization_id"
    t.index ["screen_id", "started_at"], name: "index_play_logs_on_screen_id_and_started_at"
    t.index ["screen_id"], name: "index_play_logs_on_screen_id"
  end

  create_table "profiles", force: :cascade do |t|
    t.string "brand"
    t.bigint "business_sphere_id"
    t.datetime "created_at", null: false
    t.string "holding"
    t.bigint "organization_id", null: false
    t.datetime "updated_at", null: false
    t.index ["business_sphere_id"], name: "index_profiles_on_business_sphere_id"
    t.index ["organization_id"], name: "index_profiles_on_organization_id", unique: true
  end

  create_table "rotation_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "display_duration_seconds"
    t.bigint "media_asset_id", null: false
    t.integer "position", null: false
    t.bigint "rotation_id", null: false
    t.datetime "updated_at", null: false
    t.index ["media_asset_id"], name: "index_rotation_items_on_media_asset_id"
    t.index ["rotation_id", "position"], name: "index_rotation_items_on_rotation_id_and_position", unique: true
    t.index ["rotation_id"], name: "index_rotation_items_on_rotation_id"
  end

  create_table "rotations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.boolean "system_managed", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "name"], name: "index_rotations_on_organization_id_and_name", unique: true
    t.index ["organization_id"], name: "index_rotations_on_organization_id"
  end

  create_table "screen_tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "screen_id", null: false
    t.bigint "tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["screen_id", "tag_id"], name: "index_screen_tags_on_screen_id_and_tag_id", unique: true
    t.index ["screen_id"], name: "index_screen_tags_on_screen_id"
    t.index ["tag_id"], name: "index_screen_tags_on_tag_id"
  end

  create_table "screens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "orientation", default: "landscape", null: false
    t.bigint "owner_organization_id"
    t.bigint "station_id", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_organization_id"], name: "index_screens_on_owner_organization_id"
    t.index ["station_id", "name"], name: "index_screens_on_station_id_and_name", unique: true
    t.index ["station_id"], name: "index_screens_on_station_id"
  end

  create_table "stations", force: :cascade do |t|
    t.string "agent_token_digest"
    t.datetime "created_at", null: false
    t.bigint "location_id", null: false
    t.string "name", null: false
    t.integer "offline_cache_hours", default: 24, null: false
    t.datetime "updated_at", null: false
    t.index ["location_id", "name"], name: "index_stations_on_location_id_and_name", unique: true
    t.index ["location_id"], name: "index_stations_on_location_id"
  end

  create_table "tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index "lower((name)::text)", name: "index_tags_on_lower_name", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.bigint "organization_id", null: false
    t.string "password_digest", null: false
    t.string "role", default: "manager", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["organization_id"], name: "index_users_on_organization_id"
    t.index ["role"], name: "index_users_on_role"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "advertising_order_line_days", "advertising_order_lines", on_delete: :cascade
  add_foreign_key "advertising_order_lines", "advertising_orders", on_delete: :cascade
  add_foreign_key "advertising_order_lines", "broadcast_point_groups", on_delete: :restrict
  add_foreign_key "advertising_orders", "media_assets", on_delete: :restrict
  add_foreign_key "advertising_orders", "organizations", on_delete: :restrict
  add_foreign_key "advertising_orders", "rotations", on_delete: :restrict
  add_foreign_key "advertising_orders", "users", column: "created_by_user_id", on_delete: :restrict
  add_foreign_key "airtime_bookings", "broadcast_point_groups"
  add_foreign_key "airtime_bookings", "organizations"
  add_foreign_key "broadcast_point_group_memberships", "broadcast_point_groups", on_delete: :cascade
  add_foreign_key "broadcast_point_group_memberships", "screens"
  add_foreign_key "broadcast_point_groups", "organizations"
  add_foreign_key "media_assets", "organizations"
  add_foreign_key "media_assets", "users", column: "uploaded_by_id", on_delete: :nullify
  add_foreign_key "media_plans", "advertising_order_lines", on_delete: :restrict
  add_foreign_key "media_plans", "airtime_bookings", on_delete: :restrict
  add_foreign_key "media_plans", "broadcast_point_groups", on_delete: :restrict
  add_foreign_key "media_plans", "organizations"
  add_foreign_key "media_plans", "rotations", on_delete: :restrict
  add_foreign_key "play_logs", "media_assets"
  add_foreign_key "play_logs", "organizations"
  add_foreign_key "play_logs", "screens"
  add_foreign_key "profiles", "directory_business_spheres", column: "business_sphere_id", on_delete: :restrict
  add_foreign_key "profiles", "organizations", on_delete: :cascade
  add_foreign_key "rotation_items", "media_assets", on_delete: :restrict
  add_foreign_key "rotation_items", "rotations"
  add_foreign_key "rotations", "organizations"
  add_foreign_key "screen_tags", "screens"
  add_foreign_key "screen_tags", "tags"
  add_foreign_key "screens", "organizations", column: "owner_organization_id"
  add_foreign_key "screens", "stations"
  add_foreign_key "stations", "locations"
  add_foreign_key "users", "organizations"
end
