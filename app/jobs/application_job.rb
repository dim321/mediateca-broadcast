# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  # Jobs referencing удалённые записи не должны падать бесконечно
  discard_on ActiveJob::DeserializationError

  retry_on ActiveRecord::Deadlocked, wait: 1.second, attempts: 3

  retry_on(*Media::StorageErrors::NETWORK, wait: :polynomially_longer, attempts: 8)
end
