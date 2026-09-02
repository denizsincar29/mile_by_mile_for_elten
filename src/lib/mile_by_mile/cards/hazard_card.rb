# frozen_string_literal: true

module MileByMile
  # Hazard card. Can only be played against an opponent.
  class HazardCard < Card
    TYPES = %i[stall empty_tank flat_tire accident turned_back speed_limit skip_turn].freeze

    NAMES = {
      stall: 'Stall the engine',
      empty_tank: 'Empty the tank',
      flat_tire: 'Flat tire',
      accident: 'Accident',
      turned_back: 'U-turn',
      speed_limit: 'Speed limit',
      skip_turn: 'Skip a turn'
    }.freeze

    attr_reader :type

    def initialize(type, name: nil)
      raise ArgumentError, "unknown hazard type: #{type}" unless TYPES.include?(type)

      super(name || NAMES.fetch(type))
      @type = type
    end

    def opponent_only?
      true
    end

    # accident and u-turn can't be played against a target whose car
    # isn't started or isn't currently able to move
    def requires_target_moving?
      %i[accident turned_back].include?(type)
    end
  end
end
