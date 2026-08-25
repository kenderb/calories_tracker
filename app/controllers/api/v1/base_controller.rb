module Api
  module V1
    # Shared behaviour for every v1 endpoint: authentication, and turning
    # exceptions into a consistent error body.
    class BaseController < ApplicationController
      # Errors follow RFC 9457 (problem details). One shape for every failure
      # means the React client needs a single error path, not one per endpoint.
      PROBLEM_CONTENT_TYPE = "application/problem+json".freeze

      before_action :authenticate!

      rescue_from ActiveRecord::RecordNotFound, with: :not_found
      rescue_from ActiveRecord::RecordInvalid, with: :unprocessable
      rescue_from ActionController::ParameterMissing, with: :bad_request

      attr_reader :current_user

      private

      def authenticate!
        token = bearer_token
        @current_user = User.find_by(api_token: token) if token.present?
        return if @current_user

        problem(
          status: :unauthorized,
          title: "Unauthorized",
          detail: "Provide a valid API token as `Authorization: Bearer <token>`."
        )
      end

      def bearer_token
        request.authorization.to_s[/\ABearer\s+(.+)\z/i, 1]&.strip
      end

      def problem(status:, title:, detail:, **extra)
        render status: status,
               content_type: PROBLEM_CONTENT_TYPE,
               json: { title:, detail:, status: Rack::Utils.status_code(status) }.merge(extra)
      end

      def not_found(error)
        problem(status: :not_found, title: "Not found", detail: error.message)
      end

      def unprocessable(error)
        problem(
          status: :unprocessable_content,
          title: "Validation failed",
          detail: error.message,
          errors: error.record&.errors&.to_hash(true) || {}
        )
      end

      def bad_request(error)
        problem(status: :bad_request, title: "Bad request", detail: error.message)
      end
    end
  end
end
