# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OwnedScreenPolicy do
  let(:client_org) { create(:organization, :client) }
  let(:manager) { create(:user, :manager, organization: client_org) }
  let(:accountant) { create(:user, :accountant, organization: client_org) }
  let(:other_manager) { create(:user, :manager, organization: create(:organization, :client)) }
  let(:owned_screen) { create(:screen, owner_organization: client_org) }
  let(:foreign_owned) { create(:screen, owner_organization: other_manager.organization) }
  let(:unowned) { create(:screen) }

  describe 'permissions' do
    it 'allows manager CRUD on own org screen' do
      policy = described_class.new(manager, owned_screen)
      expect(policy).to be_index
      expect(policy).to be_show
      expect(policy).to be_create
      expect(policy).to be_update
      expect(policy).to be_destroy
    end

    it 'denies accountant' do
      policy = described_class.new(accountant, owned_screen)
      expect(policy).not_to be_index
      expect(policy).not_to be_create
    end

    it 'denies mutate on another org owned screen' do
      policy = described_class.new(manager, foreign_owned)
      expect(policy).not_to be_show
      expect(policy).not_to be_update
      expect(policy).not_to be_destroy
    end

    it 'denies show on unowned fleet screen' do
      expect(described_class.new(manager, unowned)).not_to be_show
    end
  end

  describe 'Scope' do
    it 'returns only screens owned by the user organization' do
      owned_screen
      foreign_owned
      unowned

      resolved = described_class::Scope.new(manager, Screen.all).resolve

      expect(resolved).to contain_exactly(owned_screen)
    end

    it 'returns none for accountant' do
      owned_screen
      expect(described_class::Scope.new(accountant, Screen.all).resolve).to be_empty
    end
  end
end
