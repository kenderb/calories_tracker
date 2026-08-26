require "rails_helper"

RSpec.describe Meals::PhotoValidator do
  def validate(upload) = described_class.new(upload).call

  def upload_of(type: "image/jpeg", size: 1.kilobyte)
    instance_double(ActionDispatch::Http::UploadedFile, content_type: type, size: size)
  end

  describe "an acceptable photo" do
    it "returns nil, meaning nothing is wrong" do
      expect(validate(fixture_file_upload("meal.jpg", "image/jpeg"))).to be_nil
    end

    Meals::PhotoValidator::ACCEPTED_TYPES.each do |type|
      it "accepts #{type}" do
        expect(validate(upload_of(type: type))).to be_nil
      end
    end

    it "accepts a file exactly on the size limit" do
      expect(validate(upload_of(size: Meals::PhotoValidator::MAX_BYTES))).to be_nil
    end
  end

  describe "a param that is not a file at all" do
    it "rejects a plain string" do
      expect(validate("not-a-file")).to be_a(Meals::PhotoRejection::NotAFile)
    end

    it "rejects nil" do
      expect(validate(nil)).to be_a(Meals::PhotoRejection::NotAFile)
    end

    it "checks this before anything that would call file methods" do
      # The guard exists precisely so `content_type` is never sent to a String.
      expect { validate("not-a-file") }.not_to raise_error
    end
  end

  describe "a file of the wrong type" do
    it "rejects it" do
      expect(validate(upload_of(type: "application/pdf"))).to be_a(Meals::PhotoRejection::UnsupportedType)
    end

    it "hands the rejection the type it saw, so the message can name it" do
      rejection = validate(upload_of(type: "application/pdf"))

      expect(rejection.to_problem).to include(received: "application/pdf")
    end

    it "does not accept a type merely because it starts with image/" do
      expect(validate(upload_of(type: "image/tiff"))).to be_a(Meals::PhotoRejection::UnsupportedType)
    end

    it "is checked before size, since an oversized PDF is still the wrong type" do
      rejection = validate(upload_of(type: "application/pdf", size: 1.gigabyte))

      expect(rejection).to be_a(Meals::PhotoRejection::UnsupportedType)
    end
  end

  describe "a file that is too big" do
    it "rejects one byte over the limit" do
      oversized = upload_of(size: Meals::PhotoValidator::MAX_BYTES + 1)

      expect(validate(oversized)).to be_a(Meals::PhotoRejection::TooLarge)
    end

    it "hands the rejection the limit that was actually applied" do
      oversized = upload_of(size: Meals::PhotoValidator::MAX_BYTES + 1)

      expect(validate(oversized).to_problem[:detail]).to eq("`photo` must be 10MB or smaller.")
    end
  end
end
