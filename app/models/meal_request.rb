# Records that a user asked for a meal analysis, and whether that request was
# served from an existing one. Keeping this separate from Meal is what lets
# meals stay global and reusable while still tracking who uploaded what.
class MealRequest < ApplicationRecord
  belongs_to :user
  belongs_to :meal, inverse_of: :meal_requests

  scope :reused, -> { where(reused: true) }
end
