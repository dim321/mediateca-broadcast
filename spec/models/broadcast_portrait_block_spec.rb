# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: broadcast_portrait_blocks
#
#  id                    :bigint           not null, primary key
#  kind                  :string           not null
#  pick_strategy         :string
#  position              :integer          not null
#  time_of_day           :time
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  broadcast_portrait_id :bigint           not null
#  rotation_id           :bigint
#
# Indexes
#
#  index_broadcast_portrait_blocks_on_broadcast_portrait_id  (broadcast_portrait_id)
#  index_broadcast_portrait_blocks_on_portrait_and_position  (broadcast_portrait_id,position) UNIQUE
#  index_broadcast_portrait_blocks_on_rotation_id            (rotation_id)
#
# Foreign Keys
#
#  fk_rails_...  (broadcast_portrait_id => broadcast_portraits.id) ON DELETE => cascade
#  fk_rails_...  (rotation_id => rotations.id) ON DELETE => restrict
#
RSpec.describe BroadcastPortraitBlock, type: :model do
  describe "validations" do
    it "requires a positive unique position per portrait" do
      existing = create(:broadcast_portrait_block, :commercial)
      duplicate = build(
        :broadcast_portrait_block,
        :commercial,
        broadcast_portrait: existing.broadcast_portrait,
        position: existing.position
      )
      zero = build(:broadcast_portrait_block, :commercial, position: 0)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:position]).to be_present
      expect(zero).not_to be_valid
      expect(zero.errors[:position]).to be_present
    end

    it "builds a valid commercial block without rotation, pick, or time" do
      expect(build(:broadcast_portrait_block, :commercial)).to be_valid
    end

    it "rejects a commercial block with a rotation" do
      block = build(:broadcast_portrait_block, :commercial, rotation: create(:rotation))

      expect(block).not_to be_valid
      expect(block.errors[:rotation_id]).to be_present
    end

    it "requires rotation and pick strategy on a filler block" do
      missing = build(:broadcast_portrait_block, :filler, rotation: nil, pick_strategy: nil)
      valid = build(:broadcast_portrait_block, :filler)

      expect(missing).not_to be_valid
      expect(missing.errors[:rotation_id]).to be_present
      expect(missing.errors[:pick_strategy]).to be_present
      expect(valid).to be_valid
    end

    it "rejects a filler block with time_of_day" do
      block = build(:broadcast_portrait_block, :filler, time_of_day: "12:00")

      expect(block).not_to be_valid
      expect(block.errors[:time_of_day]).to be_present
    end

    it "requires rotation and time_of_day on an insertion block" do
      missing = build(:broadcast_portrait_block, :insertion, rotation: nil, time_of_day: nil)
      valid = build(:broadcast_portrait_block, :insertion)

      expect(missing).not_to be_valid
      expect(missing.errors[:rotation_id]).to be_present
      expect(missing.errors[:time_of_day]).to be_present
      expect(valid).to be_valid
    end

    it "allows pick_strategy on an insertion block" do
      expect(build(:broadcast_portrait_block, :insertion, pick_strategy: :sequential)).to be_valid
    end

    it "allows an optional rotation on service header blocks and still rejects pick or time" do
      rotation = create(:rotation)
      valid = build(:broadcast_portrait_block, :service_header_start, rotation: rotation)
      with_time = build(:broadcast_portrait_block, :service_header_start, time_of_day: "09:00")
      with_pick = build(:broadcast_portrait_block, :service_header_start, pick_strategy: :sequential)

      expect(valid).to be_valid
      expect(build(:broadcast_portrait_block, :service_header_start)).to be_valid
      expect(with_time).not_to be_valid
      expect(with_time.errors[:time_of_day]).to be_present
      expect(with_pick).not_to be_valid
      expect(with_pick.errors[:pick_strategy]).to be_present
    end
  end
end
