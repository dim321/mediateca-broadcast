# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScreenPolicy do
  let(:operator_organization) { create(:organization, :operator) }
  let(:client_user) { create(:user, organization: create(:organization, :client)) }
  let(:screen) { create(:screen, organization: operator_organization) }

  it 'denies client users from creating screens' do
    expect(described_class.new(client_user, screen)).not_to be_create
  end

  it 'scopes screens to the operator organization' do
    foreign_screen = create(:screen, organization: create(:organization, :operator))

    resolved = described_class::Scope.new(
      create(:user, organization: operator_organization),
      Screen.all
    ).resolve

    expect(resolved).to contain_exactly(screen)
    expect(resolved).not_to include(foreign_screen)
  end
end
