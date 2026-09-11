# frozen_string_literal: true

class DropAirtimeQuotasAndAddMediaPlanCancelled < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :airtime_bookings, :airtime_quotas
    remove_index :airtime_bookings, :airtime_quota_id
    remove_column :airtime_bookings, :airtime_quota_id, :bigint, null: false

    drop_table :airtime_quotas do |t|
      t.bigint :broadcast_point_group_id, null: false
      t.string :content_type
      t.datetime :ends_at, null: false
      t.integer :seconds_remaining, null: false
      t.integer :seconds_total, null: false
      t.datetime :starts_at, null: false
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.index [ :broadcast_point_group_id, :starts_at, :ends_at ],
        name: 'index_airtime_quotas_on_group_and_window'
      t.index [ :broadcast_point_group_id ],
        name: 'index_airtime_quotas_on_broadcast_point_group_id'
      t.check_constraint 'ends_at > starts_at', name: 'airtime_quotas_ends_after_starts'
      t.check_constraint 'seconds_remaining <= seconds_total',
        name: 'airtime_quotas_remaining_lte_total'
      t.check_constraint 'seconds_remaining >= 0',
        name: 'airtime_quotas_seconds_remaining_non_negative'
      t.check_constraint 'seconds_total >= 0',
        name: 'airtime_quotas_seconds_total_non_negative'
    end
  end
end
