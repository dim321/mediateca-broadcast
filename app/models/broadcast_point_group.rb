# frozen_string_literal: true

# == Schema Information
#
# Table name: broadcast_point_groups
#
#  id              :bigint           not null, primary key
#  name            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :bigint           not null
#
# Indexes
#
#  index_broadcast_point_groups_on_organization_id           (organization_id)
#  index_broadcast_point_groups_on_organization_id_and_name  (organization_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
class BroadcastPointGroup < ApplicationRecord
  belongs_to :organization

  has_many :broadcast_point_group_memberships, dependent: :destroy
  has_many :screens, through: :broadcast_point_group_memberships
  has_many :media_plans, dependent: :restrict_with_exception
  has_many :airtime_quotas, dependent: :restrict_with_exception
  has_many :airtime_bookings, dependent: :restrict_with_exception

  validates :name, presence: true, uniqueness: { scope: :organization_id }
end
