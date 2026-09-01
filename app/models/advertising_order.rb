# frozen_string_literal: true

# == Schema Information
#
# Table name: advertising_orders
#
#  id                  :bigint           not null, primary key
#  business_sphere     :string
#  clip_title          :string
#  coefficient_percent :integer          default(0), not null
#  discount_cents      :integer          default(0), not null
#  document_version    :integer          default(1), not null
#  duration_seconds    :integer
#  placement_kind      :string           default("own_atmosphere"), not null
#  product_name        :string           not null
#  status              :string           default("draft"), not null
#  total_shows         :integer          default(0), not null
#  total_sum_cents     :integer          default(0), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  created_by_user_id  :bigint           not null
#  media_asset_id      :bigint           not null
#  organization_id     :bigint           not null
#  rotation_id         :bigint           not null
#
# Indexes
#
#  index_advertising_orders_on_created_by_user_id  (created_by_user_id)
#  index_advertising_orders_on_media_asset_id      (media_asset_id)
#  index_advertising_orders_on_organization_id     (organization_id)
#  index_advertising_orders_on_rotation_id         (rotation_id) UNIQUE
#  index_advertising_orders_on_status              (status)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_user_id => users.id) ON DELETE => restrict
#  fk_rails_...  (media_asset_id => media_assets.id) ON DELETE => restrict
#  fk_rails_...  (organization_id => organizations.id) ON DELETE => restrict
#  fk_rails_...  (rotation_id => rotations.id) ON DELETE => restrict
#
class AdvertisingOrder < ApplicationRecord
  def self.ransackable_attributes(_auth_object = nil)
    %w[id business_sphere clip_title coefficient_percent discount_cents document_version duration_seconds placement_kind product_name status total_shows total_sum_cents created_at updated_at created_by_user_id media_asset_id organization_id rotation_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[organization created_by]
  end

  belongs_to :organization
  belongs_to :created_by, class_name: "User", foreign_key: :created_by_user_id,
    inverse_of: :created_advertising_orders
  belongs_to :media_asset
  belongs_to :rotation

  has_many :advertising_order_lines, dependent: :destroy
  has_many :advertising_order_line_days, through: :advertising_order_lines
  has_many :media_plans, through: :advertising_order_lines

  enum :status, {
    draft: "draft",
    pending_moderation: "pending_moderation",
    active: "active",
    completed: "completed",
    cancelled: "cancelled"
  }, default: :draft

  enum :placement_kind, {
    own_atmosphere: "own_atmosphere",
    commercial: "commercial"
  }, default: :own_atmosphere

  validates :product_name, presence: true
  validates :discount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :total_sum_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :total_shows, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :coefficient_percent, numericality: { only_integer: true }
  validates :document_version, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :rotation_id, uniqueness: true
  validate :rotation_matches_organization
  validate :rotation_is_system_managed

  before_validation :snapshot_clip_from_media_asset
  before_validation :snapshot_business_sphere_from_profile, on: :create

  private

  def snapshot_clip_from_media_asset
    return if media_asset.blank?

    if clip_title.blank? && media_asset.file.attached?
      self.clip_title = media_asset.file.filename.to_s
    end
    self.duration_seconds = media_asset.duration_seconds if duration_seconds.blank?
  end

  def snapshot_business_sphere_from_profile
    return if business_sphere.present?

    self.business_sphere = organization&.profile&.business_sphere&.name
  end

  def rotation_matches_organization
    return if rotation.blank? || organization.blank?
    return if rotation.organization_id == organization_id

    errors.add(:rotation, :wrong_organization)
  end

  def rotation_is_system_managed
    return if rotation.blank?
    return if rotation.system_managed?

    errors.add(:rotation, :must_be_system_managed)
  end
end
