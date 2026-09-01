# frozen_string_literal: true

class LocationPolicy < FleetPolicy
  # Fleet catalog stays readable; hours mutate for operator or screen owners (R7).
  def update?
    return true if operator?
    return false unless client_mutator?

    owns_screens_at_location?
  end

  private

  def owns_screens_at_location?
    Screen.joins(:station)
      .where(stations: { location_id: record.id }, owner_organization_id: user.organization_id)
      .exists?
  end
end
