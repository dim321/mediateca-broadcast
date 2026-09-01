# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Media upload", type: :system do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }

    before do
      ActiveJob::Base.queue_adapter = :test
      allow_any_instance_of(MediaAsset).to receive(:broadcast_replace_to)
      allow_any_instance_of(MediaAsset).to receive(:broadcast_update_to)
    end

  it "uploads a file and shows ready status after background job" do
    visit login_path
    fill_in I18n.t("sessions.new.email"), with: user.email
    fill_in I18n.t("sessions.new.password"), with: "password123456"
    click_button I18n.t("sessions.new.submit")

    visit root_path
    attach_file(Rails.root.join("spec/fixtures/files/1x1.png"))
    select I18n.t("media_assets.index.content_types.own"), from: "media_asset_content_type"
    select I18n.t("media_assets.index.visibilities.organization"), from: "media_asset_visibility"
    click_button I18n.t("media_assets.index.upload_submit")

    expect(page).to have_content(I18n.t("media_assets.create.created"))
    perform_enqueued_jobs
    visit current_path

    expect(page).to have_content("Ready")
  end
end
