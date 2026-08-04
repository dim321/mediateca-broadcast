# frozen_string_literal: true

# == Schema Information
#
# Table name: tags
#
#  id              :bigint           not null, primary key
#  name            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :bigint           not null
#
# Indexes
#
#  index_tags_on_organization_and_lower_name  (organization_id, lower((name)::text)) UNIQUE
#  index_tags_on_organization_id              (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
class Tag < ApplicationRecord
  belongs_to :organization

  has_many :broadcast_point_tags, dependent: :destroy
  has_many :broadcast_points, through: :broadcast_point_tags
  has_many :screen_tags, dependent: :destroy
  has_many :screens, through: :screen_tags

  validates :name, presence: true
  validates :name,
    uniqueness: { scope: :organization_id, case_sensitive: false }

  before_validation :normalize_name

  private

  def normalize_name
    self.name = name.to_s.strip
  end
end
