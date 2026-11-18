# frozen_string_literal: true

require "rails_helper"

RSpec.describe "config/recurring.yml" do # rubocop:disable RSpec/DescribeClass
  # Solid Queue marks the last hash argument as keywords. A flow sequence
  # `args: [tag: "...", cleanup: "..."]` is two hashes, so perform receives
  # two arguments and raises ArgumentError.
  def arguments_with_kwargs(args)
    if args.last.is_a?(Hash)
      args[0...-1] + [ Hash.ruby2_keywords_hash(args.last) ]
    else
      args
    end
  end

  it "schedules the database backup with one options hash" do
    config = ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/recurring.yml")).deep_symbolize_keys
    entry = config.fetch(:production).fetch(:backup_db)
    args = entry.fetch(:args)

    expect(entry.fetch(:class)).to eq("OpsBackups::BackupDbJob")
    expect(entry.fetch(:queue)).to eq("operations")
    expect(entry.fetch(:schedule)).to eq("every hour")
    expect(args).to eq([ { tag: "db_pg_backup", cleanup: "retain_tiered" } ])

    backup = instance_double(OpsBackups::Backup)
    allow(OpsBackups::Backup).to receive(:new).and_return(backup)
    allow(backup).to receive(:db_pg_backup)
    allow(OpsBackups::Backup).to receive(:retain_tiered_cleanup_policy)

    OpsBackups::BackupDbJob.new(*arguments_with_kwargs(args)).perform_now

    expect(backup).to have_received(:db_pg_backup).with(exclude_tables: [], tag: "db_pg_backup")
    expect(OpsBackups::Backup).to have_received(:retain_tiered_cleanup_policy).with(tag: "db_pg_backup")
  end
end
