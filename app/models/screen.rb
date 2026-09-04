# frozen_string_literal: true

# == Schema Information
#
# Table name: screens
#
#  id                                    :bigint           not null, primary key
#  inherit_operating_hours_from_location :boolean          default(TRUE), not null
#  name                                  :string           not null
#  operating_hours                       :jsonb            not null
#  orientation                           :string           default("landscape"), not null
#  created_at                            :datetime         not null
#  updated_at                            :datetime         not null
#  owner_organization_id                 :bigint
#  station_id                            :bigint           not null
#
# Indexes
#
#  index_screens_on_owner_organization_id  (owner_organization_id)
#  index_screens_on_station_id             (station_id)
#  index_screens_on_station_id_and_name    (station_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (owner_organization_id => organizations.id)
#  fk_rails_...  (station_id => stations.id)
#
class Screen < ApplicationRecord
  def self.ransackable_attributes(_auth_object = nil)
    %w[id name orientation created_at updated_at owner_organization_id station_id
       inherit_operating_hours_from_location]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[station owner_organization broadcast_portrait]
  end

  include Location::OperatingHours

  belongs_to :station
  belongs_to :owner_organization, class_name: "Organization", optional: true

  has_one :broadcast_portrait, dependent: :destroy, inverse_of: :screen
  has_many :screen_tags, dependent: :destroy
  has_many :tags, through: :screen_tags
  has_many :play_logs, dependent: :restrict_with_exception
  has_many :playlist_item_screens, dependent: :destroy
  has_many :broadcast_point_group_memberships, dependent: :restrict_with_exception
  has_many :broadcast_point_groups, through: :broadcast_point_group_memberships

  enum :orientation, {
    landscape: "landscape",
    portrait: "portrait"
  }, default: :landscape

  attribute :location_id, :integer
  attribute :template_id, :integer

  validates :name, presence: true, uniqueness: { scope: :station_id }
  validate :owner_organization_must_be_client
  validate :template_must_be_a_template
  validate :operating_hours_shape

  scope :operator_catalog, -> { all }
  scope :inheriting_operating_hours, -> { where(inherit_operating_hours_from_location: true) }

  delegate :location, to: :station, allow_nil: true

  before_validation :assign_default_name, on: :create
  before_validation :clear_operator_owner

  def location_id
    super.presence || station&.location_id
  end

  def operating_hours=(value)
    super(Location::OperatingHours.normalize(value))
  end

  def effective_operating_hours
    if inherit_operating_hours_from_location?
      location&.operating_hours || {}
    else
      operating_hours
    end
  end

  def assigned_template
    return if template_id.blank?

    BroadcastPortrait.templates.find_by(id: template_id)
  end

  private

  def assign_default_name
    return if name.present? || station.blank?

    self.name = station.next_screen_name
  end

  def clear_operator_owner
    return unless owner_organization&.operator?

    self.owner_organization = nil
  end

  def owner_organization_must_be_client
    return if owner_organization.blank?
    return if owner_organization.client?

    errors.add(:owner_organization, :must_be_client)
  end

  def template_must_be_a_template
    return if template_id.blank?
    return if BroadcastPortrait.templates.exists?(id: template_id)

    errors.add(:template_id, :must_be_template)
  end
end
