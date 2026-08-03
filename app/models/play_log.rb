# frozen_string_literal: true

class PlayLog < ApplicationRecord
  belongs_to :organization
  belongs_to :screen
  belongs_to :media_asset

  enum :source, {
    agent: "agent"
  }, default: :agent

  validates :started_at, :source, presence: true
end
