module Api
  module V1
    # Plain hash-building rather than a serializer gem: the output shape stays
    # directly readable next to the OpenAPI schema that documents it.
    class MealSerializer
      def initialize(meal, reused: false)
        @meal = meal
        @reused = reused
      end

      def as_json
        base = {
          id: meal.id,
          status: meal.status,
          reused: reused,
          created_at: meal.created_at.iso8601,
          analyzed_at: meal.analyzed_at&.iso8601
        }

        case meal.status
        when "succeeded" then base.merge(nutrition_payload)
        when "not_food"  then base.merge(items: [], total: zero_total)
        when "failed"    then base.merge(failure: failure_payload)
        else base
        end
      end

      private

      attr_reader :meal, :reused

      def nutrition_payload
        items = meal.items.map { |item| item_payload(item) }
        { items: items, total: total_payload(meal.items), model: model_payload }
      end

      def item_payload(item)
        {
          food_name: item.food_name,
          grams: item.grams.to_f,
          confidence: item.confidence&.to_f,
          kcal: item.kcal.to_f,
          protein_g: item.protein_g.to_f,
          carbs_g: item.carbs_g.to_f,
          fat_g: item.fat_g.to_f,
          # The reusable basis, exposed so a client can re-weigh a food without
          # another request.
          per_100g: {
            kcal: item.kcal_per_100g.to_f,
            protein_g: item.protein_per_100g.to_f,
            carbs_g: item.carbs_per_100g.to_f,
            fat_g: item.fat_per_100g.to_f
          }
        }
      end

      def total_payload(items)
        {
          kcal: items.sum(&:kcal).to_f,
          protein_g: items.sum(&:protein_g).to_f,
          carbs_g: items.sum(&:carbs_g).to_f,
          fat_g: items.sum(&:fat_g).to_f
        }
      end

      def zero_total
        { kcal: 0.0, protein_g: 0.0, carbs_g: 0.0, fat_g: 0.0 }
      end

      def model_payload
        { id: meal.model_id, latency_ms: meal.latency_ms }
      end

      def failure_payload
        { kind: meal.failure_kind, reason: meal.failure_reason }
      end
    end
  end
end
