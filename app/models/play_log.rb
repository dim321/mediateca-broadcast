# frozen_string_literal: true

# == Schema Information
#
# Table name: play_logs
#
#  id              :bigint           not null, primary key
#  source          :string           default("agent"), not null
#  started_at      :datetime         not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  media_asset_id  :bigint           not null
#  organization_id :bigint           not null
#  screen_id       :bigint           not null
#
# Indexes
#
#  index_play_logs_on_media_asset_id                  (media_asset_id)
#  index_play_logs_on_organization_id                 (organization_id)
#  index_play_logs_on_organization_id_and_started_at  (organization_id,started_at)
#  index_play_logs_on_screen_id                       (screen_id)
#  index_play_logs_on_screen_id_and_started_at        (screen_id,started_at)
#
# Foreign Keys
#
#  fk_rails_...  (media_asset_id => media_assets.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (screen_id => screens.id)
#
class PlayLog < ApplicationRecord
  def self.ransackable_attributes(_auth_object = nil)
    %w[id source started_at created_at updated_at media_asset_id organization_id screen_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[organization screen media_asset]
  end

  belongs_to :organization
  belongs_to :screen
  belongs_to :media_asset

  enum :source, {
    agent: "agent"
  }, default: :agent

  validates :started_at, :source, presence: true
end
