# frozen_string_literal: true

# == Schema Information
#
# Table name: agent_commands
#
#  id           :bigint           not null, primary key
#  command_type :string           not null
#  finished_at  :datetime
#  issued_at    :datetime         not null
#  params       :jsonb            not null
#  result_error :string
#  status       :string           default("pending"), not null
#  succeeded    :boolean
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  public_id    :string           not null
#  screen_id    :bigint           not null
#  station_id   :bigint           not null
#
# Indexes
#
#  index_agent_commands_on_public_id              (public_id) UNIQUE
#  index_agent_commands_on_screen_id              (screen_id)
#  index_agent_commands_on_station_id             (station_id)
#  index_agent_commands_on_station_id_and_status  (station_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (screen_id => screens.id)
#  fk_rails_...  (station_id => stations.id)
#
class AgentCommand < ApplicationRecord
  SCREEN_TYPES = %w[start_stream restart_stream stop wake sleep screenshot record ensure_app install_apk].freeze
  STATION_TYPES = %w[fetch_screens].freeze
  TYPES = (SCREEN_TYPES + STATION_TYPES).freeze
  UPLOAD_TYPES = %w[screenshot record].freeze

  belongs_to :station
  belongs_to :screen, optional: true

  has_one_attached :artifact

  enum :status, { pending: "pending", acked: "acked" }, default: :pending, validate: true

  validates :public_id, :command_type, :issued_at, presence: true
  validates :public_id, uniqueness: true
  validates :command_type, inclusion: { in: TYPES }
  validate :screen_matches_command_scope

  def expects_upload?
    UPLOAD_TYPES.include?(command_type)
  end

  private

  def screen_matches_command_scope
    return errors.add(:screen, :invalid) if command_type == "fetch_screens" && screen.present?
    return if command_type == "fetch_screens"
    return errors.add(:screen, :blank) if screen.blank?
    return if station.present? && screen.station_id == station_id

    errors.add(:screen, :invalid)
  end
end
