# frozen_string_literal: true

# Общий предок доменных сервисов (callable object).
class ServiceObject
  def self.call(...)
    new(...).call
  end
end
