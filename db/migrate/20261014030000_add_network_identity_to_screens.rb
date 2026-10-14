# frozen_string_literal: true

class AddNetworkIdentityToScreens < ActiveRecord::Migration[8.1]
  def change
    add_column :screens, :mac_address, :macaddr
    add_column :screens, :ip_address, :inet
    add_column :screens, :network_registered, :boolean, default: false, null: false

    add_index :screens, %i[station_id mac_address],
              unique: true,
              where: "mac_address IS NOT NULL"
    add_check_constraint :screens,
                         "ip_address IS NULL OR (family(ip_address) = 4 AND masklen(ip_address) = 32)",
                         name: "screens_ip_address_is_ipv4_host"

    change_column_null :agent_commands, :screen_id, true
    add_index :agent_commands, :station_id,
              unique: true,
              where: "status = 'pending' AND command_type = 'fetch_screens'",
              name: "index_agent_commands_on_pending_fetch_screens"
  end
end
