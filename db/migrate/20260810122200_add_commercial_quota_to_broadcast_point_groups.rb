# frozen_string_literal: true

class AddCommercialQuotaToBroadcastPointGroups < ActiveRecord::Migration[8.0]
  def change
    add_column :broadcast_point_groups, :commercial_quota_percent, :integer
    add_column :broadcast_point_groups, :commercial_quota_period, :string
  end
end
