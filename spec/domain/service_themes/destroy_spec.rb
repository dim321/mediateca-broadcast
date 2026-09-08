# frozen_string_literal: true

require "rails_helper"

RSpec.describe ServiceThemes::Destroy do
  it "destroys the theme and its four rotations when unused (AE8 inverse)" do
    theme = ServiceThemes::Create.call(organization: create(:organization, :operator), name: "Салон")
    rotation_ids = theme.rotations.map(&:id)

    described_class.call(theme: theme)

    expect(ServiceTheme.where(id: theme.id)).to be_empty
    expect(Rotation.where(id: rotation_ids)).to be_empty
  end

  it "restricts destroy when a portrait references the theme (AE8)" do
    theme = create(:service_theme)
    create(:broadcast_portrait, :for_screen, service_theme: theme)

    expect { described_class.call(theme: theme) }.to raise_error(ActiveRecord::DeleteRestrictionError)
    expect(theme.reload).to be_persisted
  end

  it "restricts destroy when a portrait block references the theme" do
    theme = create(:service_theme)
    portrait = create(:broadcast_portrait, :for_screen)
    create(:broadcast_portrait_block, :service_welcome, broadcast_portrait: portrait, service_theme: theme)

    expect { described_class.call(theme: theme) }.to raise_error(ActiveRecord::DeleteRestrictionError)
    expect(theme.reload).to be_persisted
  end
end
