# frozen_string_literal: true

require "rails_helper"

RSpec.describe Playlists::StationDateLock do
  it "uses a different advisory namespace than Airtime::ScreenLock" do
    expect(described_class::NAMESPACE).to eq(874_202)
    expect(described_class::NAMESPACE).not_to eq(Airtime::ScreenLock::NAMESPACE)
  end
end
