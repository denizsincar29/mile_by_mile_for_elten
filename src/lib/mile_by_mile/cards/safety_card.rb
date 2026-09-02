# frozen_string_literal: true

module MileByMile
  # Safety (immunity) card. Played on yourself, permanent effect.
  class SafetyCard < Card
    TYPES = %i[stall empty_tank flat_tire accident turned_back speed_limit skip_turn].freeze

    NAMES = {
      stall: 'Engine immunity',
      empty_tank: 'Fuel immunity',
      flat_tire: 'Tire immunity',
      accident: 'Accident immunity',
      turned_back: 'U-turn immunity',
      speed_limit: 'Speed limit immunity',
      skip_turn: 'Turn-skip immunity'
    }.freeze

    attr_reader :type

    def initialize(type, name: nil)
      raise ArgumentError, "unknown safety type: #{type}" unless TYPES.include?(type)

      super(name || NAMES.fetch(type))
      @type = type
    end

    def self_only?
      true
    end
  end
end
