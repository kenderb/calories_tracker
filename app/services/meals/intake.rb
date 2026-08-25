module Meals
  # Handles an upload, deciding whether it needs a model call at all.
  #
  # Meals are keyed by the SHA-256 of the image bytes, so the same photo -- from
  # this user or any other -- resolves to one analysis. What happens next
  # depends on what that analysis already is:
  #
  #   settled with an answer  serve it, no call
  #   still in flight         join it, no call (one is already queued)
  #   previously failed       retry it on the same record
  #   never seen              create it and queue the call
  class Intake
    Result = Struct.new(:meal, :meal_request, :reused, keyword_init: true) do
      alias_method :reused?, :reused
    end

    def initialize(user:, upload:)
      @user = user
      @upload = upload
    end

    def call
      checksum = Digest::SHA256.hexdigest(upload.read)
      upload.rewind

      existing = Meal.find_by(image_checksum: checksum)
      return resolve_existing(existing) if existing

      create_and_enqueue(checksum)
    end

    private

    attr_reader :user, :upload

    def resolve_existing(meal)
      if meal.failed?
        # A previous attempt failed -- most often a timeout or a rate limit.
        # Re-uploading is a reasonable request for another try, on the same
        # record so the checksum stays unique.
        meal.update!(status: :pending, failure_kind: nil, failure_reason: nil)
        AnalyzeMealJob.perform_later(meal.id)
        return build(meal, reused: false)
      end

      # Succeeded, not_food, pending, or processing: in every case there is
      # either an answer already or a call in flight. Nothing to enqueue.
      build(meal, reused: true)
    end

    def create_and_enqueue(checksum)
      meal = Meal.new(image_checksum: checksum, status: :pending)
      meal.photo.attach(upload)
      meal.save!

      AnalyzeMealJob.perform_later(meal.id)
      build(meal, reused: false)
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      # Two uploads of the same photo raced between the uniqueness check and the
      # insert. The unique index is what stops both from spending a call; the
      # loser joins the winner's analysis.
      raced = Meal.find_by(image_checksum: checksum)
      raise if raced.nil?

      build(raced, reused: true)
    end

    def build(meal, reused:)
      Result.new(
        meal: meal,
        meal_request: MealRequest.create!(user:, meal:, reused:),
        reused: reused
      )
    end
  end
end
