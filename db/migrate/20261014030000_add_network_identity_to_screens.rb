# frozen_string_literal: true

class AddNetworkIdentityToScreens < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_column :screens, :mac_address, :macaddr
    add_column :screens, :ip_address, :inet
    add_column :screens, :network_registered, :boolean, default: false, null: false

    add_index :screens, %i[station_id mac_address],
              unique: true,
              where: "mac_address IS NOT NULL",
              algorithm: :concurrently
    add_check_constraint :screens,
                         "ip_address IS NULL OR (family(ip_address) = 4 AND masklen(ip_address) = 32)",
                         name: "screens_ip_address_is_ipv4_host"

    change_column_null :agent_commands, :screen_id, true
    add_index :agent_commands, :station_id,
              unique: true,
              where: "status = 'pending' AND command_type = 'fetch_screens'",
              name: "index_agent_commands_on_pending_fetch_screens",
              algorithm: :concurrently
  end

  def down
    raise ActiveRecord::IrreversibleMigration, rollback_error if null_screen_commands?

    remove_index :agent_commands,
                 name: "index_agent_commands_on_pending_fetch_screens",
                 algorithm: :concurrently
    change_column_null :agent_commands, :screen_id, false

    remove_check_constraint :screens, name: "screens_ip_address_is_ipv4_host"
    remove_index :screens,
                 column: %i[station_id mac_address],
                 algorithm: :concurrently
    remove_column :screens, :network_registered
    remove_column :screens, :ip_address
    remove_column :screens, :mac_address
  end

  private

  def null_screen_commands?
    connection.select_value(<<~SQL)
      SELECT EXISTS (
        SELECT 1
        FROM agent_commands
        WHERE screen_id IS NULL
      )
    SQL
  end

  def rollback_error
    "Cannot restore agent_commands.screen_id NOT NULL while station-level commands have a NULL screen_id"
  end
end
