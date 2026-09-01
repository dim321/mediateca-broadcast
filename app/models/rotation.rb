# frozen_string_literal: true

# == Schema Information
#
# Table name: rotations
#
#  id              :bigint           not null, primary key
#  name            :string           not null
#  system_managed  :boolean          default(FALSE), not null
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
  def self.ransackable_attributes(_auth_object = nil)
    %w[id name system_managed created_at updated_at organization_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[organization]
  end

  belongs_to :organization
  has_many :rotation_items, dependent: :destroy
  has_many :media_assets, through: :rotation_items
  has_many :media_plans, dependent: :restrict_with_exception
  has_one :advertising_order, dependent: :restrict_with_exception

  validates :name, presence: true
  validates :name, uniqueness: { scope: :organization_id, case_sensitive: true }

  scope :managed, -> { where(system_managed: true) }
  scope :unmanaged, -> { where(system_managed: false) }

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
