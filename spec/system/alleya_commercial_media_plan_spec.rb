# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Alleya commercial media plan on Komandor screens', type: :system do
  include ActiveJob::TestHelper

  let(:clips_dir) { Pathname.new(Dir.mktmpdir('alleya-clips')) }
  let(:clip_one) { clips_dir.join('alleya_clip_1.mp4') }
  let(:clip_two) { clips_dir.join('alleya_clip_2.mp4') }

  before do
    ActiveJob::Base.queue_adapter = :test
    allow_any_instance_of(MediaAsset).to receive(:broadcast_replace_to)
    allow_any_instance_of(MediaAsset).to receive(:broadcast_update_to)
    create_advertising_network!
    generate_test_clip(clip_one, color: 'blue')
    generate_test_clip(clip_two, color: 'green')
  end

  after { FileUtils.remove_entry(clips_dir, true) }

  # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations -- one end-to-end journey
  it 'lets Alleya manager upload clips, build a rotation, and place it on Komandor vitrines' do
    sign_in_through_ui('manager@alleya.test')
    expect(page).to have_content('Аллея')

    upload_clip(clip_one)
    upload_clip(clip_two)

    alleya = Organization.find_by!(name: 'Аллея')
    expect(alleya.media_assets.ready.count).to eq(2)
    expect(alleya.media_assets.ready.all?(&:broadcast_ready?)).to be(true)

    click_link I18n.t('layouts.application.rotations')
    click_link I18n.t('rotations.index.new_rotation')
    fill_in I18n.t('rotations.form.name'), with: 'Ролики Аллеи'
    click_button I18n.t('rotations.form.submit_create')
    expect(page).to have_content(I18n.t('rotations.create.created'))

    add_ready_clip_to_rotation('alleya_clip_1.mp4')
    add_ready_clip_to_rotation('alleya_clip_2.mp4')

    rotation = Rotation.find_by!(organization: alleya, name: 'Ролики Аллеи')
    expect(rotation.media_assets.map { |asset| asset.file.filename.to_s })
      .to contain_exactly('alleya_clip_1.mp4', 'alleya_clip_2.mp4')

    click_link I18n.t('layouts.application.media_plans')
    click_link I18n.t('media_plans.index.new_media_plan')

    select 'Витрины Командор', from: 'media_plan_broadcast_point_group_id'
    select I18n.t('media_plans.form.placement_kinds.commercial'), from: 'media_plan_placement_kind'
    fill_in I18n.t('media_plans.form.shows_per_hour'), with: '6'
    select 'Ролики Аллеи', from: 'media_plan_rotation_id'
    fill_in 'media_plan_starts_at', with: '2026-08-10T10:00'
    fill_in 'media_plan_ends_at', with: '2026-08-10T11:00'
    click_button I18n.t('helpers.submit.create', model: MediaPlan.model_name.human)

    expect(page).to have_content(I18n.t('media_plans.create.created'))
    expect(page).to have_content('Ролики Аллеи')
    expect(page).to have_content('Витрины Командор')

    plan = MediaPlan.find_by!(organization: alleya, rotation: rotation)
    expect(plan).to be_active
    expect(plan).to be_commercial
    expect(plan.shows_per_hour).to eq(6)
    expect(plan.broadcast_point_group.name).to eq('Витрины Командор')
    expect(plan.airtime_booking).to be_confirmed
  end
  # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations

  def sign_in_through_ui(email, password = 'password123456')
    visit login_path
    fill_in I18n.t('sessions.new.email'), with: email
    fill_in I18n.t('sessions.new.password'), with: password
    click_button I18n.t('sessions.new.submit')
  end

  def upload_clip(path)
    visit media_assets_path
    attach_file 'media_asset[file]', path
    select I18n.t('media_assets.index.content_types.commercial'), from: 'media_asset_content_type'
    select I18n.t('media_assets.index.visibilities.organization'), from: 'media_asset_visibility'
    click_button I18n.t('media_assets.index.upload_submit')
    expect(page).to have_content(I18n.t('media_assets.create.created'))

    2.times { perform_enqueued_jobs }
    visit media_assets_path
    expect(page).to have_content(path.basename.to_s)
    asset = MediaAsset.joins(file_attachment: :blob).find_by!(active_storage_blobs: { filename: path.basename.to_s })
    expect(asset.reload).to be_ready
    expect(asset).to be_broadcast_ready
  end

  def add_ready_clip_to_rotation(filename)
    option = find('#rotation_item_media_asset_id option', text: /#{Regexp.escape(filename)}/)
    select option.text, from: 'rotation_item_media_asset_id'
    click_button I18n.t('rotations.show.add_item')
    expect(page).to have_content(I18n.t('rotation_items.create.created'))
    expect(page).to have_content(filename.sub(/\.mp4\z/, '.ts'))
  end

  def generate_test_clip(path, color:)
    success = system(
      'ffmpeg', '-y',
      '-f', 'lavfi', '-i', "color=c=#{color}:s=640x360:d=3",
      '-f', 'lavfi', '-i', 'sine=frequency=440:duration=3',
      '-shortest',
      '-c:v', 'libx264', '-pix_fmt', 'yuv420p',
      '-c:a', 'aac',
      path.to_s,
      out: File::NULL,
      err: File::NULL
    )
    raise "ffmpeg failed to generate #{path}" unless success
  end
end
