# frozen_string_literal: true

module MileByMile
  # Remedy card. Can only be played on yourself.
  class RemedyCard < Card
    TYPES = %i[start refuel repair_tire repair turn_forward remove_speed_limit].freeze

    NAMES = {
      start: 'Start the engine',
      refuel: 'Refuel',
      repair_tire: 'Fix the tire',
      repair: 'Repair after accident',
      turn_forward: 'End of U-turn',
      remove_speed_limit: 'End of speed limit'
    }.freeze

    # which hazard type this remedy cures
    CURES = {
      start: :stall,
      refuel: :empty_tank,
      repair_tire: :flat_tire,
      repair: :accident,
      turn_forward: :turned_back,
      remove_speed_limit: :speed_limit
    }.freeze

    attr_reader :type

    def initialize(type, name: nil)
      raise ArgumentError, "unknown remedy type: #{type}" unless TYPES.include?(type)

      super(name || NAMES.fetch(type))
      @type = type
    end

    def cures
      CURES.fetch(type)
    end

    def self_only?
      true
    end
  end
end
