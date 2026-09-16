# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Portraits::FrequencySet do
  def portrait_for(values)
    create(:broadcast_portrait, :for_screen, block_frequencies_per_hour: values)
  end

  it 'returns the sorted intersection of selected screens' do
    a = portrait_for([ 4, 6, 12 ]).screen
    b = portrait_for([ 2, 4, 6 ]).screen

    expect(described_class.intersection_for_screens([ a, b ])).to eq([ 4, 6 ])
  end

  it 'is empty when any screen has no overlapping values' do
    a = portrait_for([ 4 ]).screen
    b = portrait_for([ 6 ]).screen

    expect(described_class.intersection_for_screens([ a, b ])).to eq([])
  end

  it 'is empty when the list of screens is empty' do
    expect(described_class.intersection_for_screens([])).to eq([])
  end

  it 'is empty when any screen has no portrait' do
    a = portrait_for([ 4, 6 ]).screen
    b = create(:screen)

    expect(described_class.intersection_for_screens([ a, b ])).to eq([])
  end
end
