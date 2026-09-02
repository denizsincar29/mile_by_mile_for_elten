# frozen_string_literal: true

module MileByMile
  # Optional "strip all immunities" card. Played against an opponent.
  class RemoveAllSafetiesCard < Card
    def initialize
      super('Strip all immunities')
    end

    def opponent_only?
      true
    end
  end
end
