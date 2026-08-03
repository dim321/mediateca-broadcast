# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Station, type: :model do
  describe '#assign_agent_token!' do
    it 'stores a bcrypt digest and returns the token' do
      station = create(:station)

      token = station.assign_agent_token!

      expect(station.reload.agent_token_digest).to be_present
      expect(station.authenticated_with_agent_token?(token)).to be(true)
      expect(described_class.find_by_agent_token(token)).to eq(station)
    end
  end
end
