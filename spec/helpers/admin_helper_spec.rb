# frozen_string_literal: true

require "rails_helper"

RSpec.describe AdminHelper, type: :helper do
  def section_item_keys(key)
    helper.admin_nav_sections.find { |entry| entry[:key] == key }.fetch(:items).map { |item| item[:key] }
  end

  def ungrouped_item_keys
    helper.admin_nav_sections.flat_map { |section|
      next [] if section[:key].present?

      section[:items].map { |item| item[:key] }
    }
  end

  describe "#admin_nav_sections" do
    it "groups advertising orders and media plans under orders" do
      expect(section_item_keys(:orders)).to eq(%i[advertising_orders media_plans])
    end

    it "groups organizations and users under clients" do
      expect(section_item_keys(:clients)).to eq(%i[organizations users])
    end

    it "groups fleet resources under the screen fleet" do
      expect(section_item_keys(:screen_fleet)).to eq(
        %i[locations stations screens broadcast_point_groups screen_tags broadcast_point_group_memberships]
      )
    end

    it "groups media assets and rotations under the media library" do
      expect(section_item_keys(:media_library)).to eq(%i[media_assets rotations rotation_items])
    end

    it "groups business spheres and tags under directories" do
      expect(section_item_keys(:directories)).to eq(%i[business_spheres tags])
    end

    it "keeps remaining nav items outside named groups" do
      expect(ungrouped_item_keys).to eq(%i[play_logs])
    end
  end

  describe "#admin_nav_section_active?" do
    it "is true when a grouped item is current" do
      allow(helper).to receive(:controller_path).and_return("admin/media_plans")
      section = helper.admin_nav_sections.find { |entry| entry[:key] == :orders }

      expect(helper.admin_nav_section_active?(section)).to be true
    end

    it "is false when another section is current" do
      allow(helper).to receive(:controller_path).and_return("admin/organizations")
      section = helper.admin_nav_sections.find { |entry| entry[:key] == :orders }

      expect(helper.admin_nav_section_active?(section)).to be false
    end
  end
end
