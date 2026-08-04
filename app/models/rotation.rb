# frozen_string_literal: true

# == Schema Information
#
# Table name: rotations
#
#  id              :bigint           not null, primary key
#  name            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :bigint           not null
#
# Indexes
#
#  index_rotations_on_organization_id           (organization_id)
#  index_rotations_on_organization_id_and_name  (organization_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
class Rotation < ApplicationRecord
  belongs_to :organization
  has_many :rotation_items, dependent: :destroy
  has_many :media_assets, through: :rotation_items
  has_many :schedule_rules, dependent: :restrict_with_exception
  has_many :media_plans, dependent: :restrict_with_exception

  validates :name, presence: true
  validates :name, uniqueness: { scope: :organization_id, case_sensitive: true }

  def ordered_items
    if rotation_items.loaded?
      rotation_items.sort_by(&:position)
    else
      rotation_items
        .includes(media_asset: [ { file_attachment: :blob }, { broadcast_file_attachment: :blob } ])
        .order(:position)
    end
  end
end
