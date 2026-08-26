class User < ApplicationRecord
  has_many :meal_requests, dependent: :destroy
  has_many :meals, through: :meal_requests

  # Tokens are generated, never chosen, and looked up directly on each request.
  #
  # This stores the token rather than a digest, which is the weaker of the two
  # options: anyone with read access to the table can authenticate as any user.
  # It is acceptable here because the token grants nothing beyond this API and
  # the project has no password reset flow to protect. Moving to a digest means
  # a lookup by prefix plus a constant-time compare -- worth doing before this
  # ever holds real user data.
  has_secure_token :api_token

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
end
