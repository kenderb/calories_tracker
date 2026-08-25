module Nutrition
  # A whole model reply, validated before anything is persisted.
  #
  # Built from the parsed Hash that ruby_llm returns for a schema-constrained
  # response. Nothing downstream touches the raw payload -- if it did not pass
  # through here, it does not get stored.
  class Extraction
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :food_detected, :boolean, default: false
    attribute :notes, :string

    attr_reader :items

    validate :items_are_individually_valid
    validate :items_present_when_food_detected
    validate :items_absent_when_no_food_detected

    # Builds from a provider response. Keys arrive as strings; nothing here
    # assumes the payload is well-formed beyond what the schema guarantees.
    def self.from_payload(payload)
      data = (payload || {}).with_indifferent_access

      new(
        food_detected: data[:food_detected],
        notes: data[:notes],
        items: Array(data[:items])
      )
    end

    def initialize(attributes = {})
      attributes = (attributes || {}).symbolize_keys
      raw_items = attributes.delete(:items) || []
      super(attributes)
      @items = Array(raw_items).map { |item| build_item(item) }
    end

    # True when the model looked and found nothing to analyse. An answer, not a
    # failure -- callers should not treat it as an error.
    def no_food?
      !food_detected
    end

    def total_kcal
      items.sum { |item| item.kcal || 0 }
    end

    # A single string describing everything wrong, suitable for feeding back to
    # the model in a repair turn or storing as a failure reason.
    def failure_summary
      messages = errors.full_messages
      items.each_with_index do |item, index|
        next if item.valid?

        label = item.name.presence || "item #{index + 1}"
        messages += item.errors.full_messages.map { |m| "#{label}: #{m}" }
      end
      messages.uniq.join("; ")
    end

    private

    def build_item(attributes)
      attributes = (attributes || {}).symbolize_keys
      Item.new(
        name: attributes[:name],
        grams: attributes[:grams],
        kcal: attributes[:kcal],
        protein_g: attributes[:protein_g],
        carbs_g: attributes[:carbs_g],
        fat_g: attributes[:fat_g],
        confidence: attributes[:confidence]
      )
    end

    def items_are_individually_valid
      return if items.all?(&:valid?)

      errors.add(:items, "contain implausible nutrition figures")
    end

    def items_present_when_food_detected
      return unless food_detected
      return if items.any?

      errors.add(:items, "must not be empty when food was detected")
    end

    def items_absent_when_no_food_detected
      return if food_detected
      return if items.empty?

      errors.add(:items, "must be empty when no food was detected")
    end
  end
end
