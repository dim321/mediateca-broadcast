# frozen_string_literal: true

module AdvertisingOrdersHelper
  def advertising_order_day_for(line, date)
    line.advertising_order_line_days.detect { |day| day.date == date }
  end

  def advertising_grid_months(dates)
    Array(dates).group_by { |date| Date.new(date.year, date.month, 1) }
  end

  def advertising_order_price_rubles(line)
    return if line.price_per_day_cents.blank?

    line.price_per_day_cents / 100
  end

  def unoccupied_dates_for(coverage, line)
    coverage.unoccupied_days.select { |day| day.line.id == line.id }.map(&:date)
  end

  def advertising_clip_option_label(asset)
    name = asset.file.attached? ? asset.file.filename.to_s : asset.id.to_s
    "#{name} (#{asset.duration_seconds}s)"
  end
end
