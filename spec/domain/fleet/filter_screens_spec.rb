# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Fleet::FilterScreens do
  it 'returns the original scope when no tags are selected' do
    screen = create(:screen)

    expect(described_class.call(scope: Screen.all, tag_ids: [])).to contain_exactly(screen)
  end

  it 'keeps only screens that have all selected tags' do
    retail = create(:tag, name: 'retail')
    lobby = create(:tag, name: 'lobby')
    matching = create(:screen, name: 'Match')
    partial = create(:screen, name: 'Partial')
    create(:screen_tag, screen: matching, tag: retail)
    create(:screen_tag, screen: matching, tag: lobby)
    create(:screen_tag, screen: partial, tag: retail)

    result = described_class.call(scope: Screen.all, tag_ids: [ retail.id, lobby.id ])

    expect(result).to contain_exactly(matching)
  end
end
