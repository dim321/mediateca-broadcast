# frozen_string_literal: true

# == Schema Information
#
# Table name: broadcast_portraits
#
#  id                         :bigint           not null, primary key
#  block_frequencies_per_hour :integer          not null, is an Array
#  is_default                 :boolean          default(FALSE), not null
#  kind                       :string           default("cyclic"), not null
#  max_commercial_in_row      :integer          default(3), not null
#  name                       :string           not null
#  neutral_min_seconds        :integer          default(10), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  screen_id                  :bigint
#  service_theme_id           :bigint
#
# Indexes
#
#  index_broadcast_portraits_on_screen_id          (screen_id)
#  index_broadcast_portraits_on_screen_id_unique   (screen_id) UNIQUE WHERE (screen_id IS NOT NULL)
#  index_broadcast_portraits_on_service_theme_id   (service_theme_id)
#  index_broadcast_portraits_one_default_template  (is_default) UNIQUE WHERE ((screen_id IS NULL) AND is_default)
#
# Foreign Keys
#
#  fk_rails_...  (screen_id => screens.id) ON DELETE => cascade
#  fk_rails_...  (service_theme_id => service_themes.id) ON DELETE => restrict
#
class BroadcastPortrait < ApplicationRecord
  BLOCK_FREQUENCIES_PER_HOUR = [ 1, 2, 3, 4, 5, 6, 10, 12, 20 ].freeze

  def self.ransackable_attributes(_auth_object = nil)
    %w[id name kind max_commercial_in_row neutral_min_seconds is_default created_at updated_at screen_id service_theme_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[screen blocks service_theme]
  end

  belongs_to :screen, optional: true
  belongs_to :service_theme, optional: true

  has_many :blocks, class_name: "BroadcastPortraitBlock", dependent: :destroy, inverse_of: :broadcast_portrait

  scope :templates, -> { where(screen_id: nil) }

  enum :kind, {
    cyclic: "cyclic",
    timed: "timed"
  }, default: :cyclic

  before_validation :normalize_block_frequencies_per_hour

  validates :name, presence: true
  validates :kind, inclusion: { in: %w[cyclic] }
  validates :block_frequencies_per_hour, presence: true
  validates :max_commercial_in_row, numericality: { only_integer: true, greater_than: 0 }
  validates :neutral_min_seconds, inclusion: { in: [ 5, 10 ] }
  validates :screen_id, uniqueness: true, allow_nil: true
  validates :is_default, uniqueness: { conditions: -> { where(screen_id: nil, is_default: true) } },
    if: -> { is_default? && screen_id.nil? }
  validate :block_frequencies_must_be_catalog_subset
  validate :default_only_on_templates

  def self.catalog_value_for(value)
    number = Integer(value)
    return number if BLOCK_FREQUENCIES_PER_HOUR.include?(number)

    BLOCK_FREQUENCIES_PER_HOUR.select { |item| item <= number }.max || BLOCK_FREQUENCIES_PER_HOUR.first
  rescue ArgumentError, TypeError
    BLOCK_FREQUENCIES_PER_HOUR.first
  end

  def hour_slot_count
    Array(block_frequencies_per_hour).max
  end

  def template?
    screen_id.nil? && screen.nil?
  end

  private

  def normalize_block_frequencies_per_hour
    values = Array(block_frequencies_per_hour).filter_map { |item| Integer(item, exception: false) }
    self.block_frequencies_per_hour = values.uniq.sort
  end

  def block_frequencies_must_be_catalog_subset
    return if block_frequencies_per_hour.blank?

    extras = block_frequencies_per_hour - BLOCK_FREQUENCIES_PER_HOUR
    errors.add(:block_frequencies_per_hour, :inclusion) if extras.any?
  end

  def default_only_on_templates
    return unless is_default?
    return if template?

    errors.add(:is_default, :must_be_template)
  end
end
