# Runs one meal analysis out of band.
#
# The analyzer records terminal failures itself and returns normally. Only
# retryable failures propagate to here, so every `retry_on` below is reachable
# -- and each needs an exhaustion block, or a meal whose retries ran out would
# sit in `pending` forever with no job left to move it.
class AnalyzeMealJob < ApplicationJob
  queue_as :default

  # The meal was deleted while the job sat in the queue. Nothing to do.
  discard_on ActiveJob::DeserializationError

  # Order matters here. RateLimited subclasses ProviderError, and Rails picks
  # the LAST registered handler that matches -- so the broader handler must be
  # registered first, or it swallows rate limits and gives them the wrong retry
  # budget.
  #
  # A transient provider error is not especially likely to clear on its own.
  retry_on Meals::Analyzer::ProviderError,
           wait: :polynomially_longer,
           attempts: 3 do |job, error|
    settle(job, :provider_error, error)
  end

  # A rate limit does clear on its own, so it is worth waiting out: more
  # attempts, longer waits, and jitter so a burst of queued jobs does not all
  # retry in step and trip the limit again.
  retry_on Meals::Analyzer::RateLimited,
           wait: :polynomially_longer,
           attempts: 5,
           jitter: 0.3 do |job, error|
    settle(job, :rate_limited, error)
  end

  # Records the final outcome once retries are exhausted, so the meal reaches a
  # terminal state instead of being left pending.
  def self.settle(job, kind, error)
    meal = Meal.find_by(id: job.arguments.first)
    return if meal.nil? || meal.settled?

    meal.update!(
      status: :failed,
      failure_kind: kind,
      failure_reason: "gave up after #{job.executions} attempts: #{error.message}".truncate(1_000)
    )
  end

  def perform(meal_id)
    meal = Meal.find(meal_id)

    # A retry landing after the analysis already finished would spend a second
    # call for nothing. Also what makes the job idempotent.
    return if meal.settled?

    Meals::Analyzer.new(meal).call
  end
end
