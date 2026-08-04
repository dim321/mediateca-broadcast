# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScreenPolicy do
  let(:operator_user) { create(:user, organization: create(:organization, :operator)) }
  let(:client_user) { create(:user, organization: create(:organization, :client)) }
  let(:screen) { create(:screen) }

  it 'denies client users from creating screens' do
    expect(described_class.new(client_user, screen)).not_to be_create
  end

  it 'scopes all screens to operator users' do
    other_screen = create(:screen)

    resolved = described_class::Scope.new(operator_user, Screen.all).resolve

    expect(resolved).to include(screen, other_screen)
  end

  it 'scopes no screens to client users' do
    resolved = described_class::Scope.new(client_user, Screen.all).resolve

    expect(resolved).to be_empty
  end
end
