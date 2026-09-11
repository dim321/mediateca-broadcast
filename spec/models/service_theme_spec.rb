# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: service_themes
#
#  id                       :bigint           not null, primary key
#  name                     :string           not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  close_rotation_id        :bigint           not null
#  header_end_rotation_id   :bigint           not null
#  header_start_rotation_id :bigint           not null
#  organization_id          :bigint           not null
#  welcome_rotation_id      :bigint           not null
#
# Indexes
#
#  index_service_themes_on_close_rotation_id         (close_rotation_id)
#  index_service_themes_on_header_end_rotation_id    (header_end_rotation_id)
#  index_service_themes_on_header_start_rotation_id  (header_start_rotation_id)
#  index_service_themes_on_organization_id           (organization_id)
#  index_service_themes_on_organization_id_and_name  (organization_id,name) UNIQUE
#  index_service_themes_on_welcome_rotation_id       (welcome_rotation_id)
#
# Foreign Keys
#
#  fk_rails_...  (close_rotation_id => rotations.id) ON DELETE => restrict
#  fk_rails_...  (header_end_rotation_id => rotations.id) ON DELETE => restrict
#  fk_rails_...  (header_start_rotation_id => rotations.id) ON DELETE => restrict
#  fk_rails_...  (organization_id => organizations.id) ON DELETE => restrict
#  fk_rails_...  (welcome_rotation_id => rotations.id) ON DELETE => restrict
#
RSpec.describe ServiceTheme, type: :model do
  it "requires a unique name within the operator organization" do
    existing = create(:service_theme, name: "Салон красоты")
    duplicate = build(:service_theme, organization: existing.organization, name: "Салон красоты")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:name]).to be_present
    expect(build(:service_theme, organization: existing.organization, name: "Рыбный отдел")).to be_valid
  end

  it "rejects a client organization" do
    theme = build(:service_theme, organization: create(:organization, :client))

    expect(theme).not_to be_valid
    expect(theme.errors[:organization]).to be_present
  end

  it "restricts destroy when a portrait uses the theme" do
    theme = create(:service_theme)
    create(:broadcast_portrait, :for_screen, service_theme: theme)

    expect { theme.destroy! }.to raise_error(ActiveRecord::DeleteRestrictionError)
  end

  it "restricts destroy when a portrait block uses the theme" do
    theme = create(:service_theme)
    create(:broadcast_portrait_block, :service_welcome, service_theme: theme)

    expect { theme.destroy! }.to raise_error(ActiveRecord::DeleteRestrictionError)
  end
end
