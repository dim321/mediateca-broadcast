# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  # Jobs referencing удалённые записи не должны падать бесконечно
  discard_on ActiveJob::DeserializationError

  retry_on ActiveRecord::Deadlocked, wait: 1.second, attempts: 3

  retry_on Net::OpenTimeout, Net::ReadTimeout, wait: :polynomially_longer, attempts: 5
end
