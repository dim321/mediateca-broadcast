# frozen_string_literal: true

require "rails_helper"

RSpec.describe NavigationHelper, type: :helper do
  describe "#nav_link_to" do
    before { allow(helper).to receive(:controller_path).and_return("rotations") }

    it "marks the current section as active" do
      html = helper.nav_link_to("Rotations", "/rotations", controllers: %w[rotations])
      expect(html).to include("menu-active")
      expect(html).to include("Rotations")
    end

    it "does not mark inactive sections" do
      html = helper.nav_link_to("Media library", "/", controllers: %w[media_assets])
      expect(html).not_to include("menu-active")
    end
  end
end
