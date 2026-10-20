# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin screens", type: :request do
  let(:operator_org) { create(:organization, :operator) }
  let(:operator) { create(:user, :manager, organization: operator_org) }
  let(:location) { create(:location, name: "Локация 1") }
  let(:other_location) { create(:location, name: "Локация 2") }
  let!(:station) { create(:station, name: "Станция A", location: location) }
  let!(:other_station) { create(:station, name: "Станция B", location: other_location) }

  before { sign_in_as(operator) }

  describe "GET /admin/screens" do
    it "lists screens" do
      create(:screen, station: station, name: "Витрина 1")

      get admin_screens_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Витрина 1")
    end
  end

  describe "GET /admin/screens/new" do
    it "renders location, then station, then name, with a suggested name on stations" do
      get new_admin_screen_path

      expect(response).to have_http_status(:success)

      body = response.body
      location_pos = body.index("id=\"screen_location_id\"")
      station_pos = body.index("id=\"screen_station_id\"")
      name_pos = body.index("id=\"screen_name\"")

      expect(location_pos).to be_present.and be < station_pos
      expect(station_pos).to be < name_pos
      expect(body).to include("data-screen-location-select", 'data-auto-fill-name="true"')
      expect(body).to include("data-location-id=\"#{station.location_id}\"")
      expect(body).to include(
        "data-suggested-name=\"#{station.next_screen_name}\"",
        "data-suggested-name=\"#{other_station.next_screen_name}\""
      )
      expect(body).to include(%(selected="selected" value="#{operator_org.id}"))
    end
  end

  describe "GET /admin/screens/:id/edit" do
    it "preselects the screen location and does not auto-fill the name" do
      screen = create(:screen, station: station, name: "Витрина 1")

      get edit_admin_screen_path(screen)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-auto-fill-name="false"')
      expect(response.body).to include(%(selected="selected" value="#{location.id}"))
      expect(response.body).to include(%(selected="selected" value="#{station.id}"))
      expect(response.body).to include(%(selected="selected" value="#{operator_org.id}"))
    end
  end

  describe "POST /admin/screens" do
    it "creates a screen with an explicit name" do
      expect {
        post admin_screens_path, params: {
          screen: {
            location_id: location.id,
            station_id: station.id,
            name: "Витрина 1",
            orientation: "landscape"
          }
        }
      }.to change(Screen, :count).by(1)

      screen = Screen.last
      expect(screen).to have_attributes(name: "Витрина 1", station: station, owner_organization: nil)
      expect(response).to redirect_to(admin_screen_path(screen))
    end

    it "stores no owner when the operator organization is submitted" do
      expect {
        post admin_screens_path, params: {
          screen: {
            location_id: location.id,
            station_id: station.id,
            name: "Флот 1",
            orientation: "landscape",
            owner_organization_id: operator_org.id
          }
        }
      }.to change(Screen, :count).by(1)

      expect(Screen.last.owner_organization).to be_nil
    end

    it "assigns a client owner when a client is selected" do
      client = create(:organization, :client, name: "Командор")

      expect {
        post admin_screens_path, params: {
          screen: {
            location_id: location.id,
            station_id: station.id,
            name: "Витрина 1",
            orientation: "landscape",
            owner_organization_id: client.id
          }
        }
      }.to change(Screen, :count).by(1)

      expect(Screen.last.owner_organization).to eq(client)
    end

    it "fills the default name when name is omitted" do
      expect {
        post admin_screens_path, params: {
          screen: {
            location_id: location.id,
            station_id: station.id,
            orientation: "landscape"
          }
        }
      }.to change(Screen, :count).by(1)

      expect(Screen.last.name).to eq("Локация 1-Станция A-screen-1")
    end
  end

  describe "POST /admin/screens with portrait template" do
    it "copies the default portrait onto a newly created screen (AE11)" do
      template = create(:broadcast_portrait, :default, name: "Grid")
      create(:broadcast_portrait_block, :commercial, broadcast_portrait: template, position: 1)

      expect {
        post admin_screens_path, params: {
          screen: {
            location_id: location.id,
            station_id: station.id,
            name: "Витрина 1",
            orientation: "landscape"
          }
        }
      }.to change(Screen, :count).by(1)

      screen = Screen.last
      expect(response).to redirect_to(admin_screen_path(screen))
      expect(screen.broadcast_portrait.name).to eq("Grid")
      expect(screen.broadcast_portrait.blocks.map(&:kind)).to eq(%w[commercial])
      expect(screen.broadcast_portrait.is_default).to be(false)
    end

    it "still creates the screen when there is no default template" do
      post admin_screens_path, params: {
        screen: {
          location_id: location.id,
          station_id: station.id,
          name: "Витрина 1",
          orientation: "landscape"
        }
      }

      screen = Screen.last
      expect(response).to redirect_to(admin_screen_path(screen))
      expect(screen.broadcast_portrait).to be_nil
    end

    it "copies the chosen template onto a newly created screen" do
      create(:broadcast_portrait, :default, name: "Grid")
      chosen = create(:broadcast_portrait, :template, name: "Lobby grid")
      create(:broadcast_portrait_block, :commercial, broadcast_portrait: chosen, position: 1)

      post admin_screens_path, params: {
        screen: {
          location_id: location.id,
          station_id: station.id,
          name: "Витрина 1",
          orientation: "landscape",
          template_id: chosen.id
        }
      }

      screen = Screen.last
      expect(screen.broadcast_portrait.name).to eq("Lobby grid")
    end

    it "rejects assigning a screen portrait as a template" do
      other = create(:broadcast_portrait, :for_screen)

      expect {
        post admin_screens_path, params: {
          screen: {
            location_id: location.id,
            station_id: station.id,
            name: "Витрина 1",
            orientation: "landscape",
            template_id: other.id
          }
        }
      }.not_to change(Screen, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(Screen.human_attribute_name(:template_id))
    end
  end

  describe "PATCH /admin/screens" do
    include ActiveJob::TestHelper

    it "replaces the screen portrait when a template is chosen on update" do
      screen = create(:screen, station: station, name: "Витрина 1")
      create(:broadcast_portrait, :for_screen, screen: screen, name: "Old grid")
      replacement = create(:broadcast_portrait, :template, name: "Night grid")
      create(:broadcast_portrait_block, :filler, broadcast_portrait: replacement, position: 1)

      expect {
        patch admin_screen_path(screen), params: {
          screen: {
            location_id: location.id,
            station_id: station.id,
            name: screen.name,
            orientation: "landscape",
            template_id: replacement.id
          }
        }
      }.to have_enqueued_job(Playlists::GenerateForDateJob).at_least(:once)

      expect(response).to redirect_to(admin_screen_path(screen))
      expect(screen.reload.broadcast_portrait.name).to eq("Night grid")
      expect(screen.broadcast_portrait.blocks.map(&:kind)).to eq(%w[filler])
    end

    it "applies a service theme and pick strategies to the screen portrait (AE3)" do
      create(:broadcast_portrait, :default, name: "Grid")
      theme = create(:service_theme, organization: operator_org, name: "Салон")
      screen = create(:screen, station: station, name: "Витрина 1")
      create(:broadcast_portrait, :for_screen, screen: screen, name: "Old grid")

      patch admin_screen_path(screen), params: {
        screen: {
          location_id: location.id,
          station_id: station.id,
          name: screen.name,
          orientation: "landscape",
          service_theme_id: theme.id,
          header_start_pick_strategy: "random",
          welcome_pick_strategy: "ordered",
          neutral_pick_strategy: "random"
        }
      }

      portrait = screen.reload.broadcast_portrait
      expect(response).to redirect_to(admin_screen_path(screen))
      expect(portrait.service_theme).to eq(theme)
      expect(portrait.blocks.find_by!(kind: "service_header_start").pick_strategy).to eq("random")
      expect(portrait.blocks.find_by!(kind: "service_welcome").pick_strategy).to eq("ordered")
      expect(portrait.blocks.find_by!(kind: "filler").pick_strategy).to eq("random")
      expect(portrait.blocks.find_by!(kind: "service_welcome").rotation).to eq(theme.welcome_rotation)
    end

    it "enqueues regen when custom hours are saved (AE12)" do
      screen = create(:screen, station: station, name: "Витрина 1")

      expect {
        patch admin_screen_path(screen), params: {
          screen: {
            location_id: location.id,
            station_id: station.id,
            name: screen.name,
            orientation: "landscape",
            inherit_operating_hours_from_location: false,
            operating_hours: { "wed" => [ { start: "08:00", end: "22:00" } ] }
          }
        }
      }.to have_enqueued_job(Playlists::GenerateForDateJob).at_least(:once)

      expect(screen.reload.inherit_operating_hours_from_location).to be(false)
      expect(screen.operating_hours["wed"].first["start"]).to eq("08:00")
    end
  end

  describe "GET /admin/screens/new with portrait template" do
    it "renders a portrait template select and preselects the default" do
      default = create(:broadcast_portrait, :default, name: "Grid")
      create(:broadcast_portrait, :template, name: "Night")

      get new_admin_screen_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include(
        "screen_template_id",
        "Grid",
        "Night",
        %(selected="selected" value="#{default.id}"),
        "screen_service_theme_id"
      )
    end
  end

  describe "agent commands" do
    let(:screen) { create(:screen, station:) }

    it "offers only screen commands" do
      get admin_screen_path(screen)

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include(%(value="fetch_screens"))
    end

    it "queues a restart_stream that the agent poll can see" do
      token = SecureRandom.hex(16)
      station.assign_agent_token!(token)

      post admin_screen_agent_commands_path(screen), params: {
        agent_command: { command_type: "restart_stream", url: "", buffer_ms: "", seconds: "" }
      }

      expect(response).to redirect_to(admin_screen_path(screen))
      command = screen.agent_commands.pending.sole
      expect(command.command_type).to eq("restart_stream")
      expect(command.params).to eq({})

      get "/api/agent/v1/commands", headers: agent_authorization_headers(token), as: :json
      expect(response.parsed_body["commands"].map { |row| row["id"] }).to eq([ command.public_id ])
    end

    it "queues a screenshot whose upload url is on this host" do
      post admin_screen_agent_commands_path(screen), params: {
        agent_command: { command_type: "screenshot", url: "https://evil.example/put", buffer_ms: "", seconds: "" }
      }

      command = screen.agent_commands.pending.sole
      expect(command.params["upload_url"]).to include("/api/agent/uploads/")
      expect(command.params["upload_url"]).not_to include("evil.example")

      token = command.params["upload_url"].split("/uploads/").last
      put "/api/agent/uploads/#{token}", params: "png-bytes", headers: { "CONTENT_TYPE" => "image/png" }
      expect(response).to have_http_status(:no_content)
      expect(command.reload.artifact.download).to eq("png-bytes")
    end

    it "rejects a non-https apk url and leaves the queue empty" do
      post admin_screen_agent_commands_path(screen), params: {
        agent_command: { command_type: "install_apk", url: "http://files.example/app.apk", buffer_ms: "", seconds: "" }
      }

      expect(response).to redirect_to(admin_screen_path(screen))
      expect(screen.agent_commands).to be_empty
      follow_redirect!
      expect(response.body).to include(I18n.t("admin.agent_commands.errors.url_must_be_https"))
    end
  end
end
