# frozen_string_literal: true

module AdvertisingNetwork
  WEEKLY_HOURS = Location::OperatingHours::DAY_KEYS.index_with do
    [ { 'start' => '09:00', 'end' => '21:00' } ]
  end.freeze

  ELEVEN_HOURS = Location::OperatingHours::DAY_KEYS.index_with do
    [ { 'start' => '09:00', 'end' => '20:00' } ]
  end.freeze

  WEEKDAY_HOURS = %w[mon tue wed thu fri].index_with do
    [ { 'start' => '09:00', 'end' => '21:00' } ]
  end.freeze

  def create_advertising_network!
    operator = create(:organization, :operator, name: 'Advertising company')
    create(
      :user,
      :administrator,
      organization: operator,
      email: 'admin@advertising.test'
    )

    komandor = create(:organization, :client, name: 'Командор')
    alleya = create(:organization, :client, name: 'Аллея')
    create(:user, :manager, organization: komandor, email: 'manager@komandor.test')
    alleya_manager = create(:user, :manager, organization: alleya, email: 'manager@alleya.test')

    locations = [ 'Локация 1', 'Локация 2', 'Локация 3' ].map do |name|
      create(:location, name: name, operating_hours: WEEKLY_HOURS)
    end
    locations.each do |location|
      create(:station, location: location, name: 'Станция A')
      create(:station, location: location, name: 'Станция B')
    end

    station = locations.first.stations.find_by!(name: 'Станция A')
    screens = [ 'Витрина 1', 'Витрина 2', 'Витрина 3' ].map do |name|
      create(:screen, name: name, station: station, owner_organization: komandor)
    end

    group = create(
      :broadcast_point_group,
      organization: komandor,
      name: 'Витрины Командор',
      commercial_quota_percent: 60,
      commercial_quota_period: :hour
    )
    screens.each do |screen|
      create(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen)
    end

    {
      operator: operator,
      komandor: komandor,
      alleya: alleya,
      alleya_manager: alleya_manager,
      group: group,
      screens: screens
    }
  end

  def create_order_line_days!(line, dates:, shows:)
    dates.map do |date|
      create(:advertising_order_line_day, advertising_order_line: line, date: date, shows: shows)
    end
  end

  def create_group_with_hours!(organization:, hours: WEEKLY_HOURS, **group_attrs)
    location = create(:location, operating_hours: hours)
    station = create(:station, location: location)
    screen = create(:screen, station: station, owner_organization: organization)
    group = create(:broadcast_point_group, { organization: organization }.merge(group_attrs))
    create(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen)
    group
  end
end

RSpec.configure do |config|
  config.include AdvertisingNetwork
end
