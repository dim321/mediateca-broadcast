# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Organization, type: :model do
  describe 'associations' do
    it 'restricts destroy when users exist' do
      org = create(:organization)
      create(:user, organization: org)
      expect { org.destroy! }.to raise_error(ActiveRecord::DeleteRestrictionError)
    end
  end

  describe 'validations' do
    it 'requires name' do
      expect(build(:organization, name: '')).not_to be_valid
    end

    it 'requires time_zone' do
      expect(build(:organization, time_zone: '')).not_to be_valid
    end
  end

  describe 'kind' do
    it 'defaults to client' do
      expect(build(:organization)).to be_client
    end

    it 'supports operator organizations' do
      expect(build(:organization, :operator)).to be_operator
    end
  end
end
