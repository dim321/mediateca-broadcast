# frozen_string_literal: true

class RequireAirtimeBookingOnMediaPlans < ActiveRecord::Migration[8.1]
  def up
    # Pilot clean-slate (KTD8): plans without a booking cannot be gated.
    execute 'DELETE FROM media_plans WHERE airtime_booking_id IS NULL'
    change_column_null :media_plans, :airtime_booking_id, false
  end

  def down
    change_column_null :media_plans, :airtime_booking_id, true
  end
end
