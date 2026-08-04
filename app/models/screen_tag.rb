# frozen_string_literal: true

# == Schema Information
#
# Table name: screen_tags
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  screen_id  :bigint           not null
#  tag_id     :bigint           not null
#
# Indexes
#
#  index_screen_tags_on_screen_id             (screen_id)
#  index_screen_tags_on_screen_id_and_tag_id  (screen_id,tag_id) UNIQUE
#  index_screen_tags_on_tag_id                (tag_id)
#
# Foreign Keys
#
#  fk_rails_...  (screen_id => screens.id)
#  fk_rails_...  (tag_id => tags.id)
#
class ScreenTag < ApplicationRecord
  belongs_to :screen
  belongs_to :tag

  validate :same_organization

  private

  def same_organization
    return if screen.blank? || tag.blank?
    return if screen.organization_id == tag.organization_id

    errors.add(:base, :organization_mismatch)
  end
end
