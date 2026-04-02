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

ActiveRecord::Schema[8.1].define(version: 2026_04_02_123544) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "broadcast_point_tags", force: :cascade do |t|
    t.bigint "broadcast_point_id", null: false
    t.datetime "created_at", null: false
    t.bigint "tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["broadcast_point_id", "tag_id"], name: "index_broadcast_point_tags_on_broadcast_point_id_and_tag_id", unique: true
    t.index ["broadcast_point_id"], name: "index_broadcast_point_tags_on_broadcast_point_id"
    t.index ["tag_id"], name: "index_broadcast_point_tags_on_tag_id"
  end

  create_table "broadcast_points", force: :cascade do |t|
    t.string "city"
    t.datetime "created_at", null: false
    t.string "device_token_digest"
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.string "status", default: "unknown", null: false
    t.string "time_zone"
    t.datetime "updated_at", null: false
    t.string "venue_label"
    t.index ["organization_id"], name: "index_broadcast_points_on_organization_id"
  end

  create_table "media_assets", force: :cascade do |t|
    t.string "content_kind", null: false
    t.datetime "created_at", null: false
    t.integer "duration_seconds"
    t.jsonb "metadata", default: {}, null: false
    t.bigint "organization_id", null: false
    t.string "processing_status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "uploaded_by_id"
    t.index ["organization_id"], name: "index_media_assets_on_organization_id"
    t.index ["uploaded_by_id"], name: "index_media_assets_on_uploaded_by_id"
  end

  create_table "organizations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "time_zone", default: "UTC", null: false
    t.datetime "updated_at", null: false
  end

  create_table "playlist_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "display_duration_seconds"
    t.bigint "media_asset_id", null: false
    t.bigint "playlist_id", null: false
    t.integer "position", null: false
    t.datetime "updated_at", null: false
    t.index ["media_asset_id"], name: "index_playlist_items_on_media_asset_id"
    t.index ["playlist_id", "position"], name: "index_playlist_items_on_playlist_id_and_position", unique: true
    t.index ["playlist_id"], name: "index_playlist_items_on_playlist_id"
  end

  create_table "playlists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "name"], name: "index_playlists_on_organization_id_and_name", unique: true
    t.index ["organization_id"], name: "index_playlists_on_organization_id"
  end

  create_table "point_group_memberships", force: :cascade do |t|
    t.bigint "broadcast_point_id", null: false
    t.datetime "created_at", null: false
    t.bigint "point_group_id", null: false
    t.datetime "updated_at", null: false
    t.index ["broadcast_point_id"], name: "index_point_group_memberships_on_broadcast_point_id"
    t.index ["point_group_id", "broadcast_point_id"], name: "index_point_group_memberships_unique", unique: true
    t.index ["point_group_id"], name: "index_point_group_memberships_on_point_group_id"
  end

  create_table "point_groups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "name"], name: "index_point_groups_on_organization_id_and_name", unique: true
    t.index ["organization_id"], name: "index_point_groups_on_organization_id"
  end

  create_table "schedule_rules", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "ends_at", null: false
    t.bigint "organization_id", null: false
    t.bigint "playlist_id", null: false
    t.datetime "starts_at", null: false
    t.string "timezone_context", default: "organization", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "starts_at", "ends_at"], name: "idx_on_organization_id_starts_at_ends_at_962bcc92ff"
    t.index ["organization_id"], name: "index_schedule_rules_on_organization_id"
    t.index ["playlist_id"], name: "index_schedule_rules_on_playlist_id"
  end

  create_table "schedule_targets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "point_group_id", null: false
    t.bigint "schedule_rule_id", null: false
    t.datetime "updated_at", null: false
    t.index ["point_group_id"], name: "index_schedule_targets_on_point_group_id"
    t.index ["schedule_rule_id", "point_group_id"], name: "index_schedule_targets_unique", unique: true
    t.index ["schedule_rule_id"], name: "index_schedule_targets_on_schedule_rule_id"
  end

  create_table "tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.datetime "updated_at", null: false
    t.index "organization_id, lower((name)::text)", name: "index_tags_on_organization_and_lower_name", unique: true
    t.index ["organization_id"], name: "index_tags_on_organization_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.bigint "organization_id", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["organization_id"], name: "index_users_on_organization_id"
  end

  add_foreign_key "broadcast_point_tags", "broadcast_points"
  add_foreign_key "broadcast_point_tags", "tags"
  add_foreign_key "broadcast_points", "organizations"
  add_foreign_key "media_assets", "organizations"
  add_foreign_key "media_assets", "users", column: "uploaded_by_id", on_delete: :nullify
  add_foreign_key "playlist_items", "media_assets", on_delete: :restrict
  add_foreign_key "playlist_items", "playlists"
  add_foreign_key "playlists", "organizations"
  add_foreign_key "point_group_memberships", "broadcast_points"
  add_foreign_key "point_group_memberships", "point_groups"
  add_foreign_key "point_groups", "organizations"
  add_foreign_key "schedule_rules", "organizations"
  add_foreign_key "schedule_rules", "playlists", on_delete: :restrict
  add_foreign_key "schedule_targets", "point_groups"
  add_foreign_key "schedule_targets", "schedule_rules", on_delete: :cascade
  add_foreign_key "tags", "organizations"
  add_foreign_key "users", "organizations"
end
