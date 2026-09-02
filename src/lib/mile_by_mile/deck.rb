# frozen_string_literal: true

module MileByMile
  # Игровая колода: 105 карточек, или 106 с опциональной «Снять все защиты».
  class Deck
    HAZARD_TYPES = %i[stall empty_tank flat_tire accident turned_back speed_limit].freeze
    REMEDY_TYPES = %i[refuel repair_tire repair turn_forward remove_speed_limit].freeze

    def initialize(include_remove_all_safeties: false, copies: 1, seed: nil)
      copies = copies.to_i
      copies = 1 if copies < 1
      @cards = build(include_remove_all_safeties)
      @cards = Array.new(copies) { build(include_remove_all_safeties) }.flatten if copies > 1
      # сид живёт в колоде, чтобы и пополнение из сброса (refill_from)
      # оставалось детерминированным — оба клиента тасуют одинаково
      @rng = seed.nil? ? nil : Random.new(seed)
    end

    # seed делает тасовку детерминированной — оба игрока в мультиплеере
    # получают одинаковую колоду, передав один и тот же сид. Без сида (или
    # когда колода создана без сида) — случайно, как раньше.
    #
    # Тасование — собственный Fisher–Yates через rng, а не Array#shuffle!:
    # встроенный shuffle!(random:) не принимает аргумент в новом рантайме
    # Elten (src/ri), а свой алгоритм детерминирован на любом Ruby.
    def shuffle!(seed: nil)
      rng = seed.nil? ? (@rng || Random.new) : Random.new(seed)
      cards = @cards
      (cards.length - 1).downto(1) do |i|
        j = rng.rand(i + 1)
        cards[i], cards[j] = cards[j], cards[i]
      end
      self
    end

    def deal(players, count = 6)
      count.times do
        players.each { |p| p.hand << draw }
      end
      self
    end

    def draw
      @cards.pop
    end

    def size
      @cards.size
    end

    def empty?
      @cards.empty?
    end

    # Когда колода кончается, она наполняется из сброса — кроме последней
    # сброшенной карты, которая остаётся в сбросе (как в ухе). Возвращает
    # false, если наполнить нечем (в сбросе одна-единственная карта).
    def refill_from(discard_pile)
      return false if discard_pile.size < 2

      last = discard_pile.pop
      @cards.concat(discard_pile)
      discard_pile.clear
      discard_pile << last
      shuffle!
      true
    end

    private

    def build(include_remove_all_safeties)
      cards = []

      cards.concat(Array.new(10) { DistanceCard.new(25) })
      cards.concat(Array.new(10) { DistanceCard.new(50) })
      cards.concat(Array.new(10) { DistanceCard.new(75) })
      cards.concat(Array.new(12) { DistanceCard.new(100) })
      cards.concat(Array.new(4) { DistanceCard.new(200) })

      cards.concat(Array.new(10) { RemedyCard.new(:start) })
      REMEDY_TYPES.each { |t| cards.concat(Array.new(4) { RemedyCard.new(t) }) }

      HAZARD_TYPES.each { |t| cards.concat(Array.new(2) { HazardCard.new(t) }) }
      cards.concat(Array.new(10) { HazardCard.new(:skip_turn) })

      (HAZARD_TYPES + [:skip_turn]).each { |t| cards << SafetyCard.new(t) }

      cards << RemoveAllSafetiesCard.new if include_remove_all_safeties

      cards
    end
  end
end
