# frozen_string_literal: true

module Advertising
  class Coverage
    def self.occupied?(line:, date:, time_zone:)
      zone = Time.find_zone!(time_zone)
      from = zone.local(date.year, date.month, date.day)
      to = zone.local((date + 1).year, (date + 1).month, (date + 1).day)
      line.media_plans.active.where("starts_at < ? AND ends_at > ?", to, from).exists?
    end
  end
end
