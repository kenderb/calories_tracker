module Api
  module V1
    class MealsController < BaseController
      # POST /api/v1/meals
      #
      # 202 when a new analysis was queued, 200 when this exact photo has
      # already been analysed and the stored result is served instead.
      def create
        result = Meals::Intake.new(user: current_user, upload: params.expect(:photo)).call

        return render_rejection(result.rejection) if result.rejected?

        render_intake_result(result)
      end

      # GET /api/v1/meals/:id
      def show
        meal = Meal.includes(:items, :original_request).find(params[:id])

        render json: MealSerializer.new(meal).as_json, status: :ok
      end

      private

      def render_rejection(rejection)
        problem(**rejection.to_problem)
      end

      def render_intake_result(result)
        if result.reused?
          render json: serialize(result), status: :ok
        else
          response.set_header("Location", api_v1_meal_url(result.meal))
          render json: serialize(result), status: :accepted
        end
      end

      def serialize(result)
        MealSerializer.new(result.meal, reused: result.reused?).as_json
      end
    end
  end
end
