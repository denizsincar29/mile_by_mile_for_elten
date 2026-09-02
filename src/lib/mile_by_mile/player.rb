# frozen_string_literal: true

module MileByMile
  # Игрок: имя, рука карт, машина (своя или общая с командой).
  class Player
    attr_reader :name, :hand
    attr_accessor :car, :deck

    def initialize(name, car: Car.new)
      @name = name
      @hand = []
      @car = car
    end

    def has_card?(card)
      hand.include?(card)
    end

    def discard(card, pile)
      hand.delete(card)
      pile << card
    end

    def draw(deck)
      hand << deck.draw unless deck.empty?
    end

    def to_s
      name
    end
  end
end
