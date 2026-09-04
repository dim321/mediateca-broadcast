# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin broadcast portraits", type: :request do
  include ActiveJob::TestHelper

  let(:operator_org) { create(:organization, :operator) }
  let(:operator) { create(:user, :manager, organization: operator_org) }
  let(:rotation) { create(:rotation, name: "Neutral pool") }

  def portrait_attrs(overrides = {})
    {
      name: "Default grid",
      kind: "cyclic",
      block_frequency_per_hour: 4,
      max_commercial_in_row: 3,
      neutral_min_seconds: 10,
      is_default: true,
      blocks: [
        { position: 1, kind: "commercial" },
        { position: 2, kind: "filler", rotation_id: rotation.id, pick_strategy: "sequential" }
      ]
    }.merge(overrides)
  end

  describe "authentication" do
    it "redirects guests to login" do
      get admin_broadcast_portraits_path

      expect(response).to redirect_to(login_path)
    end
  end

  context "when signed in as operator" do
    before { sign_in_as(operator) }

    it "renders the Flowbite index with portrait names, not Administrate chrome" do
      create(:broadcast_portrait, name: "Lobby cycle")

      get admin_broadcast_portraits_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Lobby cycle")
      expect(response.body).to include("/assets/admin-")
      expect(response.body).not_to include("app-container")
      expect(response.body).not_to include("navigation__link")
      expect(response.body).not_to include("administrate")
    end

    it "creates a default cyclic template with commercial and sequential filler blocks" do
      expect {
        post admin_broadcast_portraits_path, params: { broadcast_portrait: portrait_attrs }
      }.to change(BroadcastPortrait, :count).by(1)

      portrait = BroadcastPortrait.find_by!(name: "Default grid")
      expect(response).to redirect_to(admin_broadcast_portrait_path(portrait))
      expect(portrait).to be_cyclic
      expect(portrait.screen_id).to be_nil
      expect(portrait.is_default).to be(true)
      expect(portrait.neutral_min_seconds).to eq(10)
      expect(portrait.blocks.order(:position).map(&:kind)).to eq(%w[commercial filler])
      expect(portrait.blocks.find_by!(position: 2).pick_strategy).to eq("sequential")
    end

    it "rejects a second default template with 422 uniqueness error" do
      create(:broadcast_portrait, :default, name: "Already default")

      expect {
        post admin_broadcast_portraits_path, params: { broadcast_portrait: portrait_attrs }
      }.not_to change(BroadcastPortrait, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(BroadcastPortrait.human_attribute_name(:is_default))
    end

    it "rejects kind=timed" do
      expect {
        post admin_broadcast_portraits_path, params: {
          broadcast_portrait: portrait_attrs.merge(name: "Timed grid", kind: "timed", is_default: false)
        }
      }.not_to change(BroadcastPortrait, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(BroadcastPortrait.where(kind: "timed")).to be_empty
    end

    it "replaces screen portrait blocks via UpsertBlocks and enqueues GenerateForDateJob" do
      screen = create(:screen)
      portrait = create(:broadcast_portrait, :for_screen, screen: screen, name: "Screen grid")
      create(:broadcast_portrait_block, :commercial, broadcast_portrait: portrait, position: 1)
      create(:broadcast_portrait_block, :filler, broadcast_portrait: portrait, position: 2, rotation: rotation)

      expect {
        patch admin_broadcast_portrait_path(portrait), params: {
          broadcast_portrait: {
            name: portrait.name,
            block_frequency_per_hour: portrait.block_frequency_per_hour,
            max_commercial_in_row: portrait.max_commercial_in_row,
            neutral_min_seconds: portrait.neutral_min_seconds,
            blocks: [
              { position: 1, kind: "filler", rotation_id: rotation.id, pick_strategy: "sequential" },
              { position: 2, kind: "commercial" }
            ]
          }
        }
      }.to have_enqueued_job(Playlists::GenerateForDateJob).at_least(:once)

      expect(response).to redirect_to(admin_broadcast_portrait_path(portrait))
      expect(portrait.blocks.order(:position).map(&:kind)).to eq(%w[filler commercial])
    end

    it "enqueues regen when a screen portrait header is saved without blocks" do
      screen = create(:screen)
      portrait = create(:broadcast_portrait, :for_screen, screen: screen, name: "Screen grid")

      expect {
        patch admin_broadcast_portrait_path(portrait), params: {
          broadcast_portrait: {
            name: "Renamed screen grid",
            block_frequency_per_hour: portrait.block_frequency_per_hour,
            max_commercial_in_row: portrait.max_commercial_in_row,
            neutral_min_seconds: portrait.neutral_min_seconds
          }
        }
      }.to have_enqueued_job(Playlists::GenerateForDateJob).at_least(:once)

      expect(portrait.reload.name).to eq("Renamed screen grid")
    end

    it "does not enqueue regen when a template is updated without a screen" do
      portrait = create(:broadcast_portrait, :template, name: "Template grid")

      expect {
        patch admin_broadcast_portrait_path(portrait), params: {
          broadcast_portrait: {
            name: "Renamed template",
            block_frequency_per_hour: portrait.block_frequency_per_hour,
            max_commercial_in_row: portrait.max_commercial_in_row,
            neutral_min_seconds: portrait.neutral_min_seconds
          }
        }
      }.not_to have_enqueued_job(Playlists::GenerateForDateJob)
    end

    it "does not reassign screen_id on a screen portrait" do
      screen = create(:screen)
      other = create(:screen)
      portrait = create(:broadcast_portrait, :for_screen, screen: screen)

      patch admin_broadcast_portrait_path(portrait), params: {
        broadcast_portrait: {
          name: portrait.name,
          screen_id: other.id,
          block_frequency_per_hour: portrait.block_frequency_per_hour,
          max_commercial_in_row: portrait.max_commercial_in_row,
          neutral_min_seconds: portrait.neutral_min_seconds
        }
      }

      expect(portrait.reload.screen_id).to eq(screen.id)
    end
  end
end
