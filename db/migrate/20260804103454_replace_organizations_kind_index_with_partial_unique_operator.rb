# frozen_string_literal: true

class ReplaceOrganizationsKindIndexWithPartialUniqueOperator < ActiveRecord::Migration[8.1]
  def change
    remove_index :organizations, :kind

    add_index :organizations,
              :kind,
              unique: true,
              where: "kind = 'operator'",
              name: 'index_organizations_one_operator'
  end
end
