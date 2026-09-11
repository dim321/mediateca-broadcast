# frozen_string_literal: true

# Generator class lives under lib/generators, not app/.
# rubocop:disable RSpec/SpecFilePathFormat

require "rails_helper"
require "rails/generators"
require "rails/generators/testing/behavior"
require "rails/generators/testing/assertions"
require "rails/generators/testing/setup_and_teardown"
require "generators/admin/scaffold/scaffold_generator"

RSpec.describe Admin::Generators::ScaffoldGenerator, type: :generator do
  include Rails::Generators::Testing::Behavior
  include Rails::Generators::Testing::SetupAndTeardown
  include Rails::Generators::Testing::Assertions
  include FileUtils

  destination Rails.root.join("tmp/generators")
  tests described_class

  before do
    prepare_destination
    FileUtils.mkdir_p(File.join(destination_root, "app/models"))
    File.write(File.join(destination_root, "app/models/widget.rb"), <<~RUBY)
      class Widget < ApplicationRecord
      end
    RUBY
  end

  it "creates an admin controller with Ransack and Kaminari" do
    run_generator %w[Widget name:string]

    controller = File.read(File.join(destination_root, "app/controllers/admin/widgets_controller.rb"))
    expect(controller).to include("class WidgetsController < Admin::BaseController")
    expect(controller).to include("Widget.ransack")
    expect(controller).to include(".page(params[:page])")
  end

  it "creates Flowbite views, a request spec, and ransackable methods without a migration" do
    run_generator %w[Widget name:string]

    index = File.read(File.join(destination_root, "app/views/admin/widgets/index.html.erb"))
    expect(index).to include("sort_link")
    expect(index).to include("paginate")
    expect(File).to exist(File.join(destination_root, "app/views/admin/widgets/_form.html.erb"))
    expect(File).to exist(File.join(destination_root, "spec/requests/admin/widgets_spec.rb"))

    model = File.read(File.join(destination_root, "app/models/widget.rb"))
    expect(model).to include("def self.ransackable_attributes")
    expect(Dir[File.join(destination_root, "db/migrate/*")]).to be_empty
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
