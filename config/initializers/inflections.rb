# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

ActiveSupport::Inflector.inflections(:en) do |inflect|
  # Default Latin rule maps quota → quotum / quota (uncountable-ish).
  inflect.irregular "quota", "quotas"
end
