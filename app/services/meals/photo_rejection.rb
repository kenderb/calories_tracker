module Meals
  # Why an upload was refused.
  #
  # One class per rule, each knowing how to explain itself. A lookup table
  # keyed by symbols can silently fall out of step with the rules it describes
  # -- add a rule, forget the entry, and the caller has nothing to render. Here
  # a rule cannot exist without its explanation, because they are the same
  # object.
  #
  # `status` is the one HTTP-shaped thing on these classes. It lives here
  # rather than in the controller so that everything about a refusal is stated
  # in one place; the controller stays a renderer.
  class PhotoRejection
    # RFC 9457 problem details, ready for the controller to render. `extra`
    # adds the specifics of this particular refusal to the body.
    def to_problem
      { status: status, title: title, detail: detail, **extra }
    end

    private

    def extra
      {}
    end

    # A `photo` param that arrived as something other than a file -- a client
    # sending JSON rather than multipart, most often.
    class NotAFile < PhotoRejection
      private

      def status = :bad_request
      def title = "Bad request"
      def detail = "`photo` must be an uploaded file."
    end

    class UnsupportedType < PhotoRejection
      def initialize(received:, accepted:)
        @received = received
        @accepted = accepted
      end

      private

      attr_reader :received, :accepted

      def status = :unsupported_media_type
      def title = "Unsupported image type"
      def detail = "`photo` must be one of: #{accepted.join(', ')}."

      # The client can see what it actually sent, which is most of the fix.
      def extra = { received: received }
    end

    class TooLarge < PhotoRejection
      def initialize(limit_bytes:)
        @limit_bytes = limit_bytes
      end

      private

      attr_reader :limit_bytes

      def status = :content_too_large
      def title = "Image too large"
      def detail = "`photo` must be #{limit_bytes / 1.megabyte}MB or smaller."
    end
  end
end
