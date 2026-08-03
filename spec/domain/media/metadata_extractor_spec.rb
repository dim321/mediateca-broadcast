# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Media::MetadataExtractor do
  describe '.call' do
    it 'keeps PNG classified as image even when ffprobe reports a video stream' do
      path = Rails.root.join('spec/fixtures/files/1x1.png').to_s

      result = described_class.call(path, declared_content_type: 'image/png')

      expect(result.refined_content_kind).to eq('image')
    end
  end
end
