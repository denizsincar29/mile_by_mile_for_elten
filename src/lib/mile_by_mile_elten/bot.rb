# frozen_string_literal: true

module MileByMileElten
  # Простой бот-соперник: на каждый ход выбирает разумную карту.
  # Приоритет: 1) наладить/завести свою машину, 2) поставить ещё не
  # выставленную защиту (сохраняет ход), 3) придержать соперника
  # вредительством, 4) ехать как можно дальше, 5) любой безопасный сброс.
  class Bot
    include MileByMile

    def initialize(game, player)
      @game = game
      @player = player
    end

    # возвращает [card, target] — что сыграть и в кого (nil для карт на себя)
    def choose_move
      hand = @player.hand
      car = @player.car
      opponents = @game.players - [@player]

      remedy = pick_self_remedy(hand, car)
      return [remedy, nil] if remedy

      safety = hand.find { |c| c.is_a?(SafetyCard) && !car.safety?(c.type) }
      return [safety, nil] if safety

      hazard, target = pick_hazard(hand, opponents)
      return [hazard, target] if hazard

      distance = pick_distance(hand, car)
      return [distance, nil] if distance

      safe_fallback(hand, opponents)
    end

    # Сколько секунд «думает» перед ходом. Простой выбор — рандом 2-4 секунды,
    # сложный (много карт движения/защит в руке) — до ~5.5 секунд.
    def think_duration
      base = 2.0 + rand * 2.0
      hand = @player.hand
      complex = hand.count { |c| c.is_a?(DistanceCard) } >= 2 ||
                hand.count { |c| c.is_a?(SafetyCard) || c.is_a?(RemedyCard) } >= 2
      complex ? base + rand * 1.5 : base
    end

    private

    def pick_self_remedy(hand, car)
      hand.find do |c|
        next false unless c.is_a?(RemedyCard)

        case c.cures
        when :stall then !car.running?
        when :turned_back then car.reversed? && car.running?
        when :speed_limit then car.speed_limited?
        else car.stalled_by?(c.cures)
        end
      end
    end

    def pick_hazard(hand, opponents)
      hazards = hand.select { |c| c.is_a?(HazardCard) }
      return nil if hazards.empty? || opponents.empty?

      leader = opponents.max_by { |p| p.car.distance }
      hazards.each do |c|
        candidates = opponents.reject { |p| p.car.safety?(c.type) }
        next if candidates.empty?

        target = candidates.include?(leader) ? leader : candidates.sample
        next unless hazard_worth_playing?(c.type, target.car)

        return [c, target]
      end
      nil
    end

    def hazard_worth_playing?(type, tcar)
      case type
      when :stall then tcar.running?
      when :empty_tank, :flat_tire then !tcar.stalled_by?(type)
      when :speed_limit then !tcar.speed_limited?
      when :accident, :turned_back then tcar.moving?
      when :skip_turn then true
      else false
      end
    end

    def pick_distance(hand, car)
      return nil unless car.moving?

      max_allowed = car.speed_limited? ? 50 : Float::INFINITY
      candidates = hand.select { |c| c.is_a?(DistanceCard) && c.miles <= max_allowed }
      return candidates.max_by(&:miles) if car.reversed?

      remaining = @game.distance_target - car.distance
      candidates.select { |c| c.miles <= remaining }.max_by(&:miles)
    end

    # гарантированно не падающий выбор: с исправленным движком карты движения
    # тоже просто уходят в отбой при невозможности сыграть, так что подходит
    # любая карта из руки — нужно только не забыть цель для вредительства
    def safe_fallback(hand, opponents)
      card = hand.first
      return [card, nil] if card.nil?

      target = card.opponent_only? && !opponents.empty? ? opponents.sample : nil
      [card, target]
    end
  end
end
