# Runs one meal analysis out of band.
#
# Retries are chosen per failure kind rather than uniformly: a rate limit wants
# a long, jittered backoff, a transient provider error a short one, and a bad
# credential no retry at all.
class AnalyzeMealJob < ApplicationJob
  queue_as :default

  # Deserialization failures mean the meal was deleted while queued; nothing to
  # do and nothing to alert on.
  discard_on ActiveJob::DeserializationError

  retry_on Meals::Analyzer::RateLimited,
           wait: :polynomially_longer,
           attempts: 5,
           jitter: 0.3

  retry_on Meals::Analyzer::ProviderError,
           wait: :polynomially_longer,
           attempts: 3

  def perform(meal_id)
    meal = Meal.find(meal_id)

    # A retry of an already-finished analysis would spend a second call for
    # nothing. Cheap guard, and it also makes the job idempotent.
    return if meal.settled?

    Meals::Analyzer.new(meal).call
  end
end
