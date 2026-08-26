module Meals
  # The rules an upload has to satisfy before it is worth reading, storing, or
  # spending a model call on. Each rule that fails hands back the
  # PhotoRejection that explains it.
  class PhotoValidator
    MAX_BYTES = 10.megabytes
    ACCEPTED_TYPES = %w[image/jpeg image/png image/webp image/heic].freeze

    def initialize(upload)
      @upload = upload
    end

    # Returns nil when the upload is usable, a PhotoRejection otherwise.
    def call
      return PhotoRejection::NotAFile.new unless uploaded_file?

      unless ACCEPTED_TYPES.include?(upload.content_type)
        return PhotoRejection::UnsupportedType.new(
          received: upload.content_type,
          accepted: ACCEPTED_TYPES
        )
      end

      return PhotoRejection::TooLarge.new(limit_bytes: MAX_BYTES) if upload.size > MAX_BYTES

      nil
    end

    private

    attr_reader :upload

    def uploaded_file?
      upload.respond_to?(:content_type) && upload.respond_to?(:size)
    end
  end
end
