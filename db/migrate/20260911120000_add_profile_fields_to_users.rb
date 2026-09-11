# frozen_string_literal: true

class AddProfileFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    change_table :users, bulk: true do |t|
      t.string :first_name
      t.string :last_name
      t.string :phone
      t.string :job_title
      t.string :telegram
      t.string :location
      t.string :status, null: false, default: "active"
    end

    add_index :users, :status
  end
end
