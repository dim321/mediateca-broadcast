# frozen_string_literal: true

require "rails_helper"

RSpec.describe "config/storage.yml" do # rubocop:disable RSpec/DescribeClass
  subject(:services) do
    YAML.safe_load(
      ERB.new(Rails.root.join("config/storage.yml").read).result,
      aliases: true
    )
  end

  around do |example|
    keys = %w[AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION AWS_S3_BUCKET AWS_ENDPOINT_URL_S3]
    originals = {}
    originals = keys.index_with { |key| ENV[key] }
    ENV["AWS_REGION"] = "ru-central-1"
    ENV["AWS_S3_BUCKET"] = "media"
    ENV["AWS_ENDPOINT_URL_S3"] = "http://192.168.1.14:9010"
    example.run
  ensure
    originals.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  it "configures rustfs as a private path-style S3 service with SSE-S3" do
    rustfs = services.fetch("rustfs")

    expect(rustfs).to include(
      "service" => "S3",
      "force_path_style" => true,
      "public" => false,
      "region" => "ru-central-1",
      "bucket" => "media",
      "request_checksum_calculation" => "when_required",
      "response_checksum_validation" => "when_required"
    )
    expect(rustfs["endpoint"]).to eq("http://192.168.1.14:9010")
    expect(rustfs.dig("upload", "server_side_encryption")).to eq("AES256")
  end
end
