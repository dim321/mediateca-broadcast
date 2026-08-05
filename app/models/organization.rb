# frozen_string_literal: true

# == Schema Information
#
# Table name: organizations
#
#  id         :bigint           not null, primary key
#  kind       :string           default("client"), not null
#  name       :string           not null
#  time_zone  :string           default("UTC"), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_organizations_one_operator  (kind) UNIQUE WHERE ((kind)::text = 'operator'::text)
#
class Organization < ApplicationRecord
  enum :kind, {
    operator: "operator",
    client: "client"
  }, default: :client

  has_many :users, inverse_of: :organization, dependent: :restrict_with_exception
  has_many :media_assets, dependent: :restrict_with_exception
  has_many :rotations, dependent: :restrict_with_exception
  has_many :broadcast_point_groups, dependent: :restrict_with_exception
  has_many :media_plans, dependent: :restrict_with_exception
  has_many :airtime_bookings, dependent: :restrict_with_exception
  has_many :play_logs, dependent: :restrict_with_exception

  validates :name, presence: true
  validates :time_zone, presence: true
  validates :kind, uniqueness: true, if: :operator?
end

