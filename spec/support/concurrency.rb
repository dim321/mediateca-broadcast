# frozen_string_literal: true

# Concurrent PG examples need real commits (no transactional fixtures) + cleanup.
RSpec.configure do |config|
  config.around(:each, :concurrency) do |example|
    previous = use_transactional_tests
    self.use_transactional_tests = false
    example.run
  ensure
    self.use_transactional_tests = previous
    conn = ActiveRecord::Base.connection
    tables = %w[
      media_plans
      airtime_bookings
      broadcast_point_group_memberships
      broadcast_point_groups
      rotation_items
      rotations
      media_assets
      users
      organizations
      screen_tags
      tags
      screens
      stations
      locations
      active_storage_attachments
      active_storage_blobs
      active_storage_variant_records
      play_logs
    ].select { |name| conn.data_source_exists?(name) }

    conn.execute("TRUNCATE #{tables.join(', ')} RESTART IDENTITY CASCADE") if tables.any?
  end
end
