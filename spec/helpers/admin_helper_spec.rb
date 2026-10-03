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
        %i[locations stations broadcast_portraits screens broadcast_point_groups screen_tags broadcast_point_group_memberships]
      )
    end

    it "lists media assets under the media library" do
      expect(section_item_keys(:media_library)).to eq(%i[media_assets])
    end

    it "groups business spheres and tags under directories" do
      expect(section_item_keys(:directories)).to eq(%i[business_spheres tags])
    end

    it "keeps remaining nav items outside named groups" do
      expect(ungrouped_item_keys).to eq(%i[play_logs])
    end
  end

  describe "#admin_advertising_order_status_class" do
    it "colors active, rejected, draft, and cancelled" do
      expect(helper.admin_advertising_order_status_class("active")).to include("bg-green-100")
      expect(helper.admin_advertising_order_status_class("rejected")).to include("bg-red-100")
      expect(helper.admin_advertising_order_status_class("draft")).to include("bg-yellow-100")
      expect(helper.admin_advertising_order_status_class("cancelled")).to include("bg-orange-100")
    end

    it "colors pending moderation blue and completed purple" do
      expect(helper.admin_advertising_order_status_class("pending_moderation")).to include("bg-blue-100")
      expect(helper.admin_advertising_order_status_class("completed")).to include("bg-purple-100")
    end

    it "renders a colored status badge" do
      order = instance_double(AdvertisingOrder, status: "active")
      allow(helper).to receive(:admin_enum_label).with(order, :status).and_return("Активен")

      badge = helper.admin_advertising_order_status_badge(order)

      expect(badge).to include("bg-green-100")
      expect(badge).to include("Активен")
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
