# frozen_string_literal: true

# == Schema Information
#
# Table name: broadcast_portraits
#
#  id                       :bigint           not null, primary key
#  block_frequency_per_hour :integer          not null
#  is_default               :boolean          default(FALSE), not null
#  kind                     :string           default("cyclic"), not null
#  max_commercial_in_row    :integer          default(3), not null
#  name                     :string           not null
#  neutral_min_seconds      :integer          default(10), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  screen_id                :bigint
#
# Indexes
#
#  index_broadcast_portraits_on_screen_id          (screen_id)
#  index_broadcast_portraits_on_screen_id_unique   (screen_id) UNIQUE WHERE (screen_id IS NOT NULL)
#  index_broadcast_portraits_one_default_template  (is_default) UNIQUE WHERE ((screen_id IS NULL) AND is_default)
#
# Foreign Keys
#
#  fk_rails_...  (screen_id => screens.id) ON DELETE => cascade
#
class BroadcastPortrait < ApplicationRecord
  def self.ransackable_attributes(_auth_object = nil)
    %w[id name kind block_frequency_per_hour max_commercial_in_row neutral_min_seconds is_default created_at updated_at screen_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[screen blocks]
  end

  belongs_to :screen, optional: true

  has_many :blocks, class_name: "BroadcastPortraitBlock", dependent: :destroy, inverse_of: :broadcast_portrait

  scope :templates, -> { where(screen_id: nil) }

  enum :kind, {
    cyclic: "cyclic",
    timed: "timed"
  }, default: :cyclic

  validates :name, presence: true
  validates :kind, inclusion: { in: %w[cyclic] }
  validates :block_frequency_per_hour, numericality: { only_integer: true, in: 1..60 }
  validates :max_commercial_in_row, numericality: { only_integer: true, greater_than: 0 }
  validates :neutral_min_seconds, inclusion: { in: [ 5, 10 ] }
  validates :screen_id, uniqueness: true, allow_nil: true
  validates :is_default, uniqueness: { conditions: -> { where(screen_id: nil, is_default: true) } },
    if: -> { is_default? && screen_id.nil? }
  validate :default_only_on_templates

  def template?
    screen_id.nil? && screen.nil?
  end

  private

  def default_only_on_templates
    return unless is_default?
    return if template?

    errors.add(:is_default, :must_be_template)
  end
end
