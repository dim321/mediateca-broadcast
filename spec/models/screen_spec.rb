# frozen_string_literal: true

require "rails_helper"

RSpec.describe Screen, type: :model do
  it "allows saving without an owner" do
    expect(build(:screen)).to be_valid
  end

  it "allows a client owner organization" do
    screen = build(:screen, owner_organization: create(:organization, :client))

    expect(screen).to be_valid
  end

  it "rejects an operator owner organization" do
    screen = build(:screen, owner_organization: create(:organization, :operator))

    expect(screen).not_to be_valid
    expect(screen.errors[:owner_organization]).to be_present
  end
end
