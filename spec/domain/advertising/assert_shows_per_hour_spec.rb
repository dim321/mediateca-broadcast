# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Advertising::AssertShowsPerHour do
  let(:order) { create(:advertising_order, shows_per_hour: 4) }

  def screen_with(values)
    create(:broadcast_portrait, :for_screen, block_frequencies_per_hour: values).screen
  end

  it 'does nothing when no screens are selected' do
    expect { described_class.call(order: order, screens: []) }.not_to raise_error
  end

  it 'rejects a disjoint set of screens' do
    expect {
      described_class.call(order: order, screens: [ screen_with([ 4 ]), screen_with([ 6 ]) ])
    }.to raise_error(Advertising::InvalidGrid)
    expect(order.errors[:advertising_order_lines]).to be_present
  end

  it 'rejects a frequency outside the intersection' do
    screens = [ screen_with([ 4, 6 ]), screen_with([ 6, 12 ]) ]
    order.shows_per_hour = 4
    expect { described_class.call(order: order, screens: screens) }.to raise_error(Advertising::InvalidGrid)
    expect(order.errors[:shows_per_hour]).to be_present
  end

  it 'allows a frequency in the intersection' do
    screens = [ screen_with([ 4, 6 ]), screen_with([ 6, 12 ]) ]
    order.shows_per_hour = 6
    expect { described_class.call(order: order, screens: screens) }.not_to raise_error
  end
end
