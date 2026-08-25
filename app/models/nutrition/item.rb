module Nutrition
  # One food from a model's reply, validated against physical reality.
  #
  # The JSON schema already guarantees these fields exist and are numbers. What
  # it cannot check is whether the numbers describe a food that could exist,
  # which is what this class is for.
  class Item
    include ActiveModel::Model
    include ActiveModel::Attributes

    # Atwater factors: the energy the body extracts per gram of each macro.
    KCAL_PER_GRAM_PROTEIN = 4
    KCAL_PER_GRAM_CARB    = 4
    KCAL_PER_GRAM_FAT     = 9

    # How far stated calories may drift from the macro arithmetic before we stop
    # believing the extraction. Some slack is legitimate -- fibre, sugar
    # alcohols, and rounding all move the number a little -- but an order of
    # magnitude does not come from rounding.
    ENERGY_TOLERANCE = 0.25

    # Pure fat is 900 kcal/100g. Nothing edible exceeds it, so anything above is
    # arithmetic that went wrong rather than an unusual food.
    MAX_KCAL_PER_100G = 900

    # Below this the macro arithmetic is dominated by rounding, so comparing it
    # to stated calories produces false alarms rather than signal.
    MIN_KCAL_FOR_ENERGY_CHECK = 10

    attribute :name, :string
    attribute :grams, :decimal
    attribute :kcal, :decimal
    attribute :protein_g, :decimal
    attribute :carbs_g, :decimal
    attribute :fat_g, :decimal
    attribute :confidence, :decimal

    validates :name, presence: true
    validates :grams, numericality: { greater_than: 0, less_than_or_equal_to: 5_000 }
    validates :kcal, :protein_g, :carbs_g, :fat_g,
              numericality: { greater_than_or_equal_to: 0 }
    validates :confidence,
              numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 },
              allow_nil: true

    validate :energy_matches_macros
    validate :energy_density_is_physically_possible

    # Calories implied by the macros, independent of what the model claimed.
    def implied_kcal
      return nil if protein_g.nil? || carbs_g.nil? || fat_g.nil?

      (protein_g * KCAL_PER_GRAM_PROTEIN) +
        (carbs_g * KCAL_PER_GRAM_CARB) +
        (fat_g * KCAL_PER_GRAM_FAT)
    end

    def kcal_per_100g
      per_100g(kcal)
    end

    # The reusable basis: this food's nutrition independent of portion size.
    def to_per_100g
      {
        kcal_per_100g: per_100g(kcal),
        protein_per_100g: per_100g(protein_g),
        carbs_per_100g: per_100g(carbs_g),
        fat_per_100g: per_100g(fat_g)
      }
    end

    private

    def per_100g(value)
      return nil if value.nil? || grams.nil? || grams.zero?

      (value / grams * 100).round(2)
    end

    # The check that catches a well-formed, confident, wrong answer.
    def energy_matches_macros
      return if kcal.nil? || implied_kcal.nil?

      # A near-zero-calorie food (celery, black coffee) has no meaningful
      # denominator: rounding macros to one decimal swamps the comparison. This
      # is the only exemption -- a small portion is still checked, because a
      # 4g item claiming 25 kcal from 1g of fat is wrong regardless of size.
      basis = [ kcal, implied_kcal ].max
      return if basis < MIN_KCAL_FOR_ENERGY_CHECK

      drift = (kcal - implied_kcal).abs / basis
      return if drift <= ENERGY_TOLERANCE

      errors.add(
        :kcal,
        "of #{kcal.to_f.round(1)} does not match its macros " \
        "(#{implied_kcal.to_f.round(1)} kcal by Atwater factors, " \
        "#{(drift * 100).to_f.round(1)}% apart)"
      )
    end

    def energy_density_is_physically_possible
      density = kcal_per_100g
      return if density.nil? || density <= MAX_KCAL_PER_100G

      errors.add(
        :kcal,
        "implies #{density.to_f.round} kcal/100g, above the #{MAX_KCAL_PER_100G} " \
        "kcal/100g of pure fat"
      )
    end
  end
end
