# frozen_string_literal: true

class CreateAirtimeQuotasAndBookings < ActiveRecord::Migration[8.1]
  def change
    create_table :airtime_quotas do |t|
      t.references :broadcast_point_group, null: false, foreign_key: true
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.integer :seconds_total, null: false
      t.integer :seconds_remaining, null: false
      t.string :content_type
      t.timestamps
    end

    add_index :airtime_quotas, [ :broadcast_point_group_id, :starts_at, :ends_at ],
      name: 'index_airtime_quotas_on_group_and_window'
    add_check_constraint :airtime_quotas, 'seconds_remaining >= 0',
      name: 'airtime_quotas_seconds_remaining_non_negative'
    add_check_constraint :airtime_quotas, 'seconds_total >= 0',
      name: 'airtime_quotas_seconds_total_non_negative'
    add_check_constraint :airtime_quotas, 'ends_at > starts_at',
      name: 'airtime_quotas_ends_after_starts'
    add_check_constraint :airtime_quotas, 'seconds_remaining <= seconds_total',
      name: 'airtime_quotas_remaining_lte_total'

    create_table :airtime_bookings do |t|
      t.references :airtime_quota, null: false, foreign_key: { to_table: :airtime_quotas }
      t.references :organization, null: false, foreign_key: true
      t.references :broadcast_point_group, null: false, foreign_key: true
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.integer :seconds, null: false
      t.string :status, null: false, default: 'confirmed'
      t.timestamps
    end

    add_index :airtime_bookings, [ :organization_id, :starts_at, :ends_at ]
    add_index :airtime_bookings, :status
    add_check_constraint :airtime_bookings, 'seconds > 0',
      name: 'airtime_bookings_seconds_positive'
    add_check_constraint :airtime_bookings, 'ends_at > starts_at',
      name: 'airtime_bookings_ends_after_starts'

    add_column :media_plans, :status, :string, null: false, default: 'active'
    add_reference :media_plans, :airtime_booking, null: true,
      foreign_key: { to_table: :airtime_bookings, on_delete: :restrict }
    add_index :media_plans, :status
  end
end
