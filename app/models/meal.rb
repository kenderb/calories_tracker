# A single analysed photo.
#
# Meals are deliberately global: no user_id, no per-user scoping. The same
# photo of the same apple has the same nutrition regardless of who uploaded it,
# so the analysis is shared and each upload costs at most one model call across
# the whole system. Attribution lives on MealRequest.
class Meal < ApplicationRecord
  has_one_attached :photo
  has_many :items, class_name: "MealItem", dependent: :destroy
  has_many :meal_requests, dependent: :destroy

  # The upload that brought this analysis into existence. Every later request
  # for the same photo is a reuse, so the earliest one is the upload that
  # actually spent the model call -- and the only meaningful answer to "who
  # uploaded this?". Meals are readable by anyone, so this is what makes an
  # analysis traceable back to a person.
  has_one :original_request, -> { order(:id) },
          class_name: "MealRequest", inverse_of: :meal

  # pending    queued, not yet picked up
  # processing a worker is mid-call
  # succeeded  extraction passed both the schema and the plausibility checks
  # not_food   the model looked and found no food -- an answer, not a failure
  # failed     see failure_kind
  enum :status, {
    pending: "pending",
    processing: "processing",
    succeeded: "succeeded",
    not_food: "not_food",
    failed: "failed"
  }, validate: true

  # Why an analysis failed, which decides whether retrying is worth anything.
  enum :failure_kind, {
    provider_error: "provider_error",         # 5xx or timeout -- retryable
    rate_limited: "rate_limited",             # 429 -- retryable, back off harder
    invalid_extraction: "invalid_extraction", # well-formed but implausible
    content_filtered: "content_filtered",     # provider refused the content
    configuration_error: "configuration_error" # bad key, unknown model -- needs a human
  }, prefix: true, allow_nil: true

  validates :image_checksum, presence: true, uniqueness: true

  scope :reusable, -> { where(status: [ :succeeded, :not_food ]) }

  # True once there is nothing more to wait for, whatever the outcome.
  def settled?
    succeeded? || not_food? || failed?
  end

  def total_kcal
    items.sum(&:kcal)
  end
end
