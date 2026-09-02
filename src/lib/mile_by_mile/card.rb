# frozen_string_literal: true

module MileByMile
  # Базовый класс любой игровой карточки.
  class Card
    attr_reader :name

    def initialize(name)
      @name = name
    end

    def to_s
      name
    end

    # играется только на соперника
    def opponent_only?
      false
    end

    # играется только на самого себя
    def self_only?
      false
    end
  end
end
