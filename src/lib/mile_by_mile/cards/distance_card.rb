# frozen_string_literal: true

module MileByMile
  # Distance (mileage) card: 25, 50, 75, 100, 200.
  class DistanceCard < Card
    VALID_MILES = [25, 50, 75, 100, 200].freeze

    attr_reader :miles

    def initialize(miles)
      raise ArgumentError, "invalid miles value: #{miles}" unless VALID_MILES.include?(miles)

      super("#{miles} miles")
      @miles = miles
    end
  end
end
