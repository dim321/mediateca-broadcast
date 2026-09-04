# frozen_string_literal: true

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
FactoryBot.define do
  factory :service_theme do
    organization { Organization.find_by(kind: "operator") || create(:organization, :operator) }
    sequence(:name) { |n| "Theme #{n}" }
    header_start_rotation { association :rotation, :system_managed, organization: organization }
    header_end_rotation { association :rotation, :system_managed, organization: organization }
    welcome_rotation { association :rotation, :system_managed, organization: organization }
    close_rotation { association :rotation, :system_managed, organization: organization }
  end
end
