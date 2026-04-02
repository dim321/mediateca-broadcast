# frozen_string_literal: true

class CreateOrganizationsUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :organizations do |t|
      t.string :name, null: false
      t.string :time_zone, null: false, default: 'UTC'

      t.timestamps
    end

    create_table :users do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :email, null: false
      t.string :password_digest, null: false

      t.timestamps
    end

    add_index :users, :email, unique: true
  end
end
