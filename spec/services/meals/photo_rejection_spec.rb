require "rails_helper"

RSpec.describe Meals::PhotoRejection do
  describe Meals::PhotoRejection::NotAFile do
    subject(:problem) { described_class.new.to_problem }

    it "answers 400, because the request itself is malformed" do
      expect(problem[:status]).to eq(:bad_request)
    end

    it "says what `photo` should have been" do
      expect(problem[:detail]).to eq("`photo` must be an uploaded file.")
    end

    it "adds nothing beyond the standard problem fields" do
      expect(problem.keys).to contain_exactly(:status, :title, :detail)
    end
  end

  describe Meals::PhotoRejection::UnsupportedType do
    subject(:problem) do
      described_class.new(received: "application/pdf", accepted: %w[image/jpeg image/png]).to_problem
    end

    it "answers 415" do
      expect(problem[:status]).to eq(:unsupported_media_type)
    end

    it "lists the types it would have taken" do
      expect(problem[:detail]).to eq("`photo` must be one of: image/jpeg, image/png.")
    end

    it "reports what was received, so the client can see what it sent" do
      expect(problem[:received]).to eq("application/pdf")
    end
  end

  describe Meals::PhotoRejection::TooLarge do
    subject(:problem) { described_class.new(limit_bytes: 10.megabytes).to_problem }

    it "answers 413" do
      expect(problem[:status]).to eq(:content_too_large)
    end

    it "states the limit it was given, in megabytes" do
      expect(problem[:detail]).to eq("`photo` must be 10MB or smaller.")
    end

    it "states whatever limit is actually in force, not a hardcoded one" do
      detail = described_class.new(limit_bytes: 2.megabytes).to_problem[:detail]

      expect(detail).to eq("`photo` must be 2MB or smaller.")
    end
  end

  it "gives every rejection the three fields RFC 9457 requires" do
    # A rejection that cannot describe itself is one the controller cannot
    # render, so this covers the whole hierarchy rather than one class.
    rejections = [
      Meals::PhotoRejection::NotAFile.new,
      Meals::PhotoRejection::UnsupportedType.new(received: "application/pdf", accepted: []),
      Meals::PhotoRejection::TooLarge.new(limit_bytes: 1.megabyte)
    ]

    rejections.each do |rejection|
      expect(rejection.to_problem).to include(:status, :title, :detail)
    end
  end

  it "keeps the reasons private -- `to_problem` is the whole public surface" do
    expect(Meals::PhotoRejection::NotAFile.new.public_methods(false)).to be_empty
  end
end
