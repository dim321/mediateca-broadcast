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
      block_frequencies_per_hour: [ 4 ],
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

    it "omits unbound theme rotations from the portrait block picker" do
      ordinary = rotation
      theme = create(:service_theme, organization: operator_org, name: "Салон красоты")
      hidden = theme.welcome_rotation
      hidden.update!(name: "Salon · welcome")

      get new_admin_broadcast_portrait_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include(ordinary.name)
      expect(response.body).to include("Салон красоты")
      expect(response.body).to include("broadcast_portrait[blocks][][service_theme_id]")
      expect(response.body).not_to include(hidden.name)
    end

    it "keeps a bound service theme selected when editing a screen portrait" do
      theme = create(:service_theme, organization: operator_org, name: "Салон красоты")
      screen = create(:screen)
      portrait = create(:broadcast_portrait, :for_screen, screen: screen)
      create(:broadcast_portrait_block, :service_welcome, broadcast_portrait: portrait, service_theme: theme)

      get edit_admin_broadcast_portrait_path(portrait)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Салон красоты")
      expect(response.body).to include(%(value="#{theme.id}" selected))
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
            block_frequencies_per_hour: portrait.block_frequencies_per_hour,
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

    it "clears service_theme_id when screen portrait blocks are edited (AE9)" do
      theme = create(:service_theme, organization: operator_org)
      screen = create(:screen)
      portrait = create(:broadcast_portrait, :for_screen, screen: screen, service_theme: theme)

      patch admin_broadcast_portrait_path(portrait), params: {
        broadcast_portrait: {
          name: portrait.name,
          block_frequencies_per_hour: portrait.block_frequencies_per_hour,
          max_commercial_in_row: portrait.max_commercial_in_row,
          neutral_min_seconds: portrait.neutral_min_seconds,
          blocks: [ { position: 1, kind: "commercial" } ]
        }
      }

      expect(portrait.reload.service_theme).to be_nil
    end

    it "creates a template with a welcome block bound to a service theme folder" do
      theme = create(:service_theme, organization: operator_org, name: "Салон")

      expect {
        post admin_broadcast_portraits_path, params: {
          broadcast_portrait: portrait_attrs.merge(
            name: "Service grid",
            is_default: false,
            blocks: [
              { position: 1, kind: "commercial" },
              { position: 2, kind: "service_welcome", service_theme_id: theme.id, pick_strategy: "random" }
            ]
          )
        }
      }.to change(BroadcastPortrait, :count).by(1)

      portrait = BroadcastPortrait.find_by!(name: "Service grid")
      welcome = portrait.blocks.find_by!(kind: "service_welcome")
      expect(response).to redirect_to(admin_broadcast_portrait_path(portrait))
      expect(welcome).to have_attributes(
        service_theme: theme,
        rotation: theme.welcome_rotation,
        pick_strategy: "random"
      )
    end

    it "enqueues regen when a screen portrait header is saved without blocks" do
      screen = create(:screen)
      portrait = create(:broadcast_portrait, :for_screen, screen: screen, name: "Screen grid")

      expect {
        patch admin_broadcast_portrait_path(portrait), params: {
          broadcast_portrait: {
            name: "Renamed screen grid",
            block_frequencies_per_hour: portrait.block_frequencies_per_hour,
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
            block_frequencies_per_hour: portrait.block_frequencies_per_hour,
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
          block_frequencies_per_hour: portrait.block_frequencies_per_hour,
          max_commercial_in_row: portrait.max_commercial_in_row,
          neutral_min_seconds: portrait.neutral_min_seconds
        }
      }

      expect(portrait.reload.screen_id).to eq(screen.id)
    end
  end
end
