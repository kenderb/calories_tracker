module Api
  module V1
    class MealsController < BaseController
      MAX_PHOTO_BYTES = 10.megabytes
      ACCEPTED_TYPES = %w[image/jpeg image/png image/webp image/heic].freeze

      # POST /api/v1/meals
      #
      # 202 when a new analysis was queued, 200 when this exact photo has
      # already been analysed and the stored result is served instead.
      def create
        upload = params.require(:photo)
        reject_unusable_upload(upload) and return

        result = Meals::Intake.new(user: current_user, upload: upload).call

        if result.reused?
          render json: serialize(result), status: :ok
        else
          response.set_header("Location", api_v1_meal_url(result.meal))
          render json: serialize(result), status: :accepted
        end
      end

      # GET /api/v1/meals/:id
      def show
        meal = Meal.includes(:items).find(params[:id])

        render json: MealSerializer.new(meal).as_json, status: :ok
      end

      private

      def serialize(result)
        MealSerializer.new(result.meal, reused: result.reused?).as_json
      end

      # Returns truthy when it has already rendered, so the caller can bail.
      def reject_unusable_upload(upload)
        unless upload.respond_to?(:content_type)
          return problem(
            status: :bad_request,
            title: "Bad request",
            detail: "`photo` must be an uploaded file."
          )
        end

        unless ACCEPTED_TYPES.include?(upload.content_type)
          return problem(
            status: :unsupported_media_type,
            title: "Unsupported image type",
            detail: "`photo` must be one of: #{ACCEPTED_TYPES.join(', ')}.",
            received: upload.content_type
          )
        end

        return unless upload.size > MAX_PHOTO_BYTES

        problem(
          status: :payload_too_large,
          title: "Image too large",
          detail: "`photo` must be #{MAX_PHOTO_BYTES / 1.megabyte}MB or smaller."
        )
      end
    end
  end
end
