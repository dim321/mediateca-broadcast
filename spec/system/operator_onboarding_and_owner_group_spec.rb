# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Operator onboarding and owner group', type: :system do
  let(:operator_password) { 'password123456' }
  let(:manager_password) { 'password123456' }
  let(:operator_email) { 'admin@advertising.test' }
  let(:komandor_manager_email) { 'manager@komandor.test' }
  let(:alleya_manager_email) { 'manager@alleya.test' }

  # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations -- one end-to-end journey
  it 'lets an operator admin provision clients and a Komandor manager own screens in a quota group' do
    operator = create(:organization, :operator, name: 'Advertising company')
    create(
      :user,
      :administrator,
      organization: operator,
      email: operator_email,
      password: operator_password
    )

    sign_in_through_ui(operator_email, operator_password)
    visit admin_root_path
    expect(page).to have_current_path(admin_root_path)

    create_client_organization('Командор')
    create_client_organization('Аллея')

    expect(Organization.client.where(name: %w[Командор Аллея]).count).to eq(2)

    [ 'Локация 1', 'Локация 2', 'Локация 3' ].each do |location_name|
      create_location_with_hours(location_name)
    end

    Location.order(:name).each do |location|
      create_station(location, 'Станция A')
      create_station(location, 'Станция B')
    end

    expect(Location.count).to eq(3)
    expect(Station.count).to eq(6)

    create_manager_for('Командор', komandor_manager_email)
    create_manager_for('Аллея', alleya_manager_email)

    expect(User.manager.joins(:organization).where(organizations: { name: %w[Командор Аллея] }).count).to eq(2)

    visit root_path
    click_button I18n.t('layouts.application.sign_out')
    expect(page).to have_current_path(login_path)

    sign_in_through_ui(komandor_manager_email, manager_password)
    expect(page).to have_content('Командор')

    location = Location.find_by!(name: 'Локация 1')
    station = location.stations.find_by!(name: 'Станция A')

    [ 'Витрина 1', 'Витрина 2', 'Витрина 3' ].each do |screen_name|
      create_owned_screen(screen_name, location:, station:)
    end

    komandor = Organization.find_by!(name: 'Командор')
    expect(komandor.owned_screens.where(station:).pluck(:name)).to contain_exactly('Витрина 1', 'Витрина 2', 'Витрина 3')

    click_link I18n.t('layouts.application.owned_broadcast_point_groups')
    click_link I18n.t('owned_broadcast_point_groups.index.new_group')

    fill_in 'broadcast_point_group_name', with: 'Витрины Командор'
    fill_in I18n.t('owned_broadcast_point_groups.form.commercial_quota_percent'), with: '60'
    find('#broadcast_point_group_commercial_quota_period option[value="hour"]').select_option
    click_button I18n.t('owned_broadcast_point_groups.form.submit')

    expect(page).to have_content(I18n.t('owned_broadcast_point_groups.create.created'))
    expect(page).to have_content('Витрины Командор')
    expect(page).to have_content(
      I18n.t('owned_broadcast_point_groups.show.quota_summary', percent: 60, period: 'hour')
    )

    komandor.owned_screens.where(station:).find_each do |screen|
      check "add_owned_screen_#{screen.id}"
    end
    click_button I18n.t('owned_broadcast_point_groups.show.add_selected')

    expect(page).to have_content(I18n.t('owned_broadcast_point_groups.add_screens.screens_added', count: 3))
    expect(page).to have_content('Витрина 1')
    expect(page).to have_content('Витрина 2')
    expect(page).to have_content('Витрина 3')

    group = BroadcastPointGroup.find_by!(organization: komandor, name: 'Витрины Командор')
    expect(group).to have_attributes(commercial_quota_percent: 60, commercial_quota_period: 'hour')
    expect(group.screens.pluck(:name)).to contain_exactly('Витрина 1', 'Витрина 2', 'Витрина 3')
  end
  # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations

  def sign_in_through_ui(email, password)
    visit login_path
    fill_in I18n.t('sessions.new.email'), with: email
    fill_in I18n.t('sessions.new.password'), with: password
    click_button I18n.t('sessions.new.submit')
  end

  def create_client_organization(name)
    visit new_admin_organization_path
    fill_in 'organization_name', with: name
    select I18n.t('enums.organization.kind.client'), from: 'organization_kind'
    submit_admin_form
    expect(page).to have_content(name)
  end

  def create_location_with_hours(name)
    visit new_admin_location_path
    fill_in 'location_name', with: name
    find('input[data-operating-hours-day="mon"][data-operating-hours-part="start"]').set('09:00')
    find('input[data-operating-hours-day="mon"][data-operating-hours-part="end"]').set('21:00')
    submit_admin_form
    expect(page).to have_content(name)
  end

  def create_station(location, name)
    visit new_admin_station_path
    fill_in 'station_name', with: name
    select location.name, from: 'station_location_id'
    submit_admin_form
    expect(page).to have_content(name)
  end

  def create_manager_for(organization_name, email)
    visit new_admin_user_path
    fill_in 'user_email', with: email
    select organization_name, from: 'user_organization_id'
    fill_in 'user_password', with: manager_password
    fill_in 'user_password_confirmation', with: manager_password
    select I18n.t('enums.user.role.manager'), from: 'user_role'
    submit_admin_form
    expect(page).to have_content(email)
  end

  def create_owned_screen(name, location:, station:)
    click_link I18n.t('layouts.application.owned_screens')
    click_link I18n.t('owned_screens.index.new_screen')
    select location.name, from: 'location_id'
    select "#{station.name} (#{location.name})", from: 'screen_station_id'
    fill_in 'screen_name', with: name
    click_button I18n.t('helpers.submit.create', model: Screen.model_name.human)
    expect(page).to have_content(I18n.t('owned_screens.create.created'))
    expect(page).to have_content(name)
  end

  def submit_admin_form
    within('form') { find('input[type=submit]').click }
  end
end
