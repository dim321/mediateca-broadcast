# frozen_string_literal: true

module QueryCountHelpers
  def count_sql_queries
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      next if payload[:cached]

      sql = payload[:sql].to_s
      next if sql.match?(/\A\s*(SAVEPOINT|RELEASE|ROLLBACK)|pg_advisory|SCHEMA|TRANSACTION/i)

      count += 1
    end
    result = yield
    [ result, count ]
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end
end

RSpec.configure do |config|
  config.include QueryCountHelpers, file_path: %r{spec/requests/performance/}
end
