# frozen_string_literal: true

# == Schema Information
#
# Table name: screens
#
#  id                                    :bigint           not null, primary key
#  inherit_operating_hours_from_location :boolean          default(TRUE), not null
#  ip_address                            :inet
#  mac_address                           :macaddr
#  name                                  :string           not null
#  network_registered                    :boolean          default(FALSE), not null
#  operating_hours                       :jsonb            not null
#  orientation                           :string           default("landscape"), not null
#  created_at                            :datetime         not null
#  updated_at                            :datetime         not null
#  owner_organization_id                 :bigint
#  station_id                            :bigint           not null
#
# Indexes
#
#  index_screens_on_owner_organization_id       (owner_organization_id)
#  index_screens_on_station_id                  (station_id)
#  index_screens_on_station_id_and_mac_address  (station_id,mac_address) UNIQUE WHERE (mac_address IS NOT NULL)
#  index_screens_on_station_id_and_name         (station_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (owner_organization_id => organizations.id)
#  fk_rails_...  (station_id => stations.id)
#
class Screen < ApplicationRecord
  def self.ransackable_attributes(_auth_object = nil)
    %w[id name orientation created_at updated_at owner_organization_id station_id
       inherit_operating_hours_from_location mac_address ip_address network_registered]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[station owner_organization broadcast_portrait]
  end

  include Location::OperatingHours

  belongs_to :station
  has_one :telemetry_snapshot, class_name: "ScreenTelemetrySnapshot", dependent: :destroy
  has_many :agent_commands, dependent: :destroy
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
  attribute :service_theme_id, :integer
  attribute :header_start_pick_strategy, :string, default: "sequential"
  attribute :header_end_pick_strategy, :string, default: "sequential"
  attribute :welcome_pick_strategy, :string, default: "sequential"
  attribute :close_pick_strategy, :string, default: "sequential"
  attribute :neutral_pick_strategy, :string, default: "sequential"

  validates :name, presence: true, uniqueness: { scope: :station_id }
  validates :mac_address, uniqueness: { scope: :station_id }, allow_nil: true
  validate :audio_station_may_have_only_one_screen
  validate :must_not_leave_audio_station_without_screen, if: :will_save_change_to_station_id?
  validate :owner_organization_must_be_client
  validate :template_must_be_a_template
  validate :service_theme_must_exist
  validate :operating_hours_shape
  validate :ip_address_is_ipv4_host

  scope :operator_catalog, -> { all }
  scope :inheriting_operating_hours, -> { where(inherit_operating_hours_from_location: true) }

  delegate :location, to: :station, allow_nil: true

  before_validation :assign_default_name, on: :create
  before_validation :clear_operator_owner
  before_destroy :prevent_destroying_sole_audio_screen

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

  def assigned_service_theme
    return if service_theme_id.blank?

    ServiceTheme.find_by(id: service_theme_id)
  end

  def service_pick_strategies
    {
      header_start: header_start_pick_strategy,
      header_end: header_end_pick_strategy,
      welcome: welcome_pick_strategy,
      close: close_pick_strategy,
      neutral: neutral_pick_strategy
    }
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

  def audio_station_may_have_only_one_screen
    return unless station&.audio?
    return unless station.screens.where.not(id: id).exists?

    errors.add(:station_id, :audio_station_full)
  end

  def must_not_leave_audio_station_without_screen
    previous_station = Station.find_by(id: station_id_in_database)
    return unless previous_station&.audio?
    return if previous_station.screens.where.not(id: id).exists?

    errors.add(:base, :audio_pseudo_screen_required)
  end

  def prevent_destroying_sole_audio_screen
    return unless station&.audio?
    return if station.screens.where.not(id: id).exists?

    errors.add(:base, :audio_pseudo_screen_required)
    throw :abort
  end

  def template_must_be_a_template
    return if template_id.blank?
    return if BroadcastPortrait.templates.exists?(id: template_id)

    errors.add(:template_id, :must_be_template)
  end

  def service_theme_must_exist
    return if service_theme_id.blank?
    return if ServiceTheme.exists?(id: service_theme_id)

    errors.add(:service_theme_id, :must_be_theme)
  end

  def ip_address_is_ipv4_host
    raw_address = ip_address_before_type_cast
    return if raw_address.blank?

    address = IPAddr.new(raw_address.to_s)
    return if address.ipv4? && address.prefix == 32 && !cidr_string?(raw_address)

    errors.add(:ip_address, :invalid)
  rescue IPAddr::InvalidAddressError, IPAddr::InvalidPrefixError
    errors.add(:ip_address, :invalid)
  end

  def cidr_string?(address)
    address.is_a?(String) && address.include?("/")
  end
end
