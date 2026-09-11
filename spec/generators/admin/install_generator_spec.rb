# frozen_string_literal: true

# Generator class lives under lib/generators, not app/.
# rubocop:disable RSpec/SpecFilePathFormat

require "rails_helper"
require "rails/generators"
require "rails/generators/testing/behavior"
require "rails/generators/testing/assertions"
require "rails/generators/testing/setup_and_teardown"
require "generators/admin/install/install_generator"

RSpec.describe Admin::Generators::InstallGenerator, type: :generator do
  include Rails::Generators::Testing::Behavior
  include Rails::Generators::Testing::SetupAndTeardown
  include Rails::Generators::Testing::Assertions
  include FileUtils

  destination Rails.root.join("tmp/generators")
  tests described_class

  before { prepare_destination }

  it "copies the operator layout and Stimulus controllers" do
    run_generator

    %w[
      app/helpers/admin_helper.rb
      app/views/layouts/admin/operator.html.erb
      app/javascript/admin/controllers/sidebar_controller.js
      app/javascript/admin/controllers/modal_controller.js
      app/javascript/admin/controllers/tabs_controller.js
      app/views/kaminari/admin/_paginator.html.erb
    ].each do |path|
      expect(File).to exist(File.join(destination_root, path))
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
