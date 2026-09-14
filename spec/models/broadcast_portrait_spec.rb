# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: broadcast_portraits
#
#  id                         :bigint           not null, primary key
#  block_frequencies_per_hour :integer          not null, is an Array
#  is_default                 :boolean          default(FALSE), not null
#  kind                       :string           default("cyclic"), not null
#  max_commercial_in_row      :integer          default(3), not null
#  name                       :string           not null
#  neutral_min_seconds        :integer          default(10), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  screen_id                  :bigint
#  service_theme_id           :bigint
#
# Indexes
#
#  index_broadcast_portraits_on_screen_id          (screen_id)
#  index_broadcast_portraits_on_screen_id_unique   (screen_id) UNIQUE WHERE (screen_id IS NOT NULL)
#  index_broadcast_portraits_on_service_theme_id   (service_theme_id)
#  index_broadcast_portraits_one_default_template  (is_default) UNIQUE WHERE ((screen_id IS NULL) AND is_default)
#
# Foreign Keys
#
#  fk_rails_...  (screen_id => screens.id) ON DELETE => cascade
#  fk_rails_...  (service_theme_id => service_themes.id) ON DELETE => restrict
#
RSpec.describe BroadcastPortrait, type: :model do
  describe "validations" do
    it "defaults to cyclic kind with commercial row cap 3 and 10-second neutrals" do
      portrait = create(:broadcast_portrait)

      expect(portrait).to be_cyclic
      expect(portrait.max_commercial_in_row).to eq(3)
      expect(portrait.neutral_min_seconds).to eq(10)
      expect(portrait.is_default).to be(false)
    end

    it "requires a name" do
      portrait = build(:broadcast_portrait, name: "")

      expect(portrait).not_to be_valid
      expect(portrait.errors[:name]).to be_present
    end

    it "rejects timed kind" do
      portrait = build(:broadcast_portrait, kind: :timed)

      expect(portrait).not_to be_valid
      expect(portrait.errors[:kind]).to be_present
    end

    it "normalizes frequencies to a unique sorted catalog subset" do
      portrait = build(:broadcast_portrait, block_frequencies_per_hour: [ 6, 4, 4 ])

      expect(portrait).to be_valid
      expect(portrait.block_frequencies_per_hour).to eq([ 4, 6 ])
    end

    it "rejects an empty frequency set" do
      portrait = build(:broadcast_portrait, block_frequencies_per_hour: [])

      expect(portrait).not_to be_valid
      expect(portrait.errors[:block_frequencies_per_hour]).to be_present
    end

    it "rejects a frequency outside the catalog" do
      portrait = build(:broadcast_portrait, block_frequencies_per_hour: [ 4, 8 ])

      expect(portrait).not_to be_valid
      expect(portrait.errors[:block_frequencies_per_hour]).to be_present
    end

    it "maps legacy scalars onto the catalog (8 -> 6)" do
      expect(described_class.catalog_value_for(4)).to eq(4)
      expect(described_class.catalog_value_for(8)).to eq(6)
      expect(described_class.catalog_value_for(0)).to eq(1)
    end

    it "rejects a non-positive max commercial in a row" do
      portrait = build(:broadcast_portrait, max_commercial_in_row: 0)

      expect(portrait).not_to be_valid
      expect(portrait.errors[:max_commercial_in_row]).to be_present
    end

    it "rejects a neutral minimum other than 5 or 10 seconds" do
      portrait = build(:broadcast_portrait, neutral_min_seconds: 7)

      expect(portrait).not_to be_valid
      expect(portrait.errors[:neutral_min_seconds]).to be_present
    end

    it "allows a 5-second neutral minimum" do
      expect(build(:broadcast_portrait, neutral_min_seconds: 5)).to be_valid
    end

    it "rejects is_default on a screen portrait" do
      portrait = build(:broadcast_portrait, :for_screen, is_default: true)

      expect(portrait).not_to be_valid
      expect(portrait.errors[:is_default]).to be_present
    end

    it "allows only one portrait per screen" do
      existing = create(:broadcast_portrait, :for_screen)
      duplicate = build(:broadcast_portrait, screen: existing.screen)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:screen_id]).to be_present
    end

    it "allows only one default template" do
      create(:broadcast_portrait, :default)
      duplicate = build(:broadcast_portrait, :default)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:is_default]).to be_present
    end

    it "allows additional non-default templates" do
      create(:broadcast_portrait, :default)

      expect(build(:broadcast_portrait, :template)).to be_valid
    end
  end

  describe "associations" do
    it "destroys blocks with the portrait" do
      portrait = create(:broadcast_portrait)
      create(:broadcast_portrait_block, broadcast_portrait: portrait)

      expect { portrait.destroy! }.to change(BroadcastPortraitBlock, :count).by(-1)
    end

    it "belongs to an optional screen" do
      screen = create(:screen)
      portrait = create(:broadcast_portrait, :for_screen, screen: screen)

      expect(portrait.screen).to eq(screen)
      expect(screen.broadcast_portrait).to eq(portrait)
    end
  end
end
