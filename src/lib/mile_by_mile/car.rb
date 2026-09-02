# frozen_string_literal: true

module MileByMile
  # Состояние машины (или общей машины команды).
  class Car
    IMMOBILIZING = %i[stall empty_tank flat_tire accident].freeze

    attr_reader :distance, :safeties

    def initialize
      @distance = 0
      @running = false
      @active_hazards = {} # IMMOBILIZING типы => true
      @safeties = {}
      @speed_limited = false
      @reversed = false
      @skip_turns = 0
    end

    def running?
      @running
    end

    # заведена и ничего не мешает ехать прямо сейчас
    def moving?
      running? && @active_hazards.empty?
    end

    def stalled_by?(type)
      @active_hazards.key?(type)
    end

    def reversed?
      @reversed
    end

    def speed_limited?
      @speed_limited
    end

    def safety?(type)
      @safeties.key?(type)
    end

    def add_safety(type)
      already_had = safety?(type)
      @safeties[type] = true
      !already_had
    end

    def clear_safeties!
      @safeties.clear
    end

    def skip_next_turn?
      @skip_turns.positive?
    end

    # сколько ходов подряд пропустит из-за накопленных карт «пропуск хода»
    def skip_turns
      @skip_turns
    end

    # применяется на цель (соперника)
    def apply_hazard!(type)
      case type
      when *IMMOBILIZING
        @active_hazards[type] = true
        @running = false
      when :turned_back
        @reversed = true
      when :speed_limit
        @speed_limited = true
      when :skip_turn
        @skip_turns += 1
      else
        raise ArgumentError, "неизвестное вредительство: #{type}"
      end
    end

    # применяется игроком на себя
    def apply_remedy!(type)
      case type
      when :start
        @running = true
        @active_hazards.delete(:stall)
      when :refuel
        @active_hazards.delete(:empty_tank)
      when :repair_tire
        @active_hazards.delete(:flat_tire)
      when :repair
        # починка после аварии убирает аварию, но мотор не заводит —
        # нужно отдельно сыграть «Завестись» (как в ухе)
        @active_hazards.delete(:accident)
      when :turn_forward
        raise RuleViolation, 'the car must be repaired and started first' unless running?

        @reversed = false
      when :remove_speed_limit
        @speed_limited = false
      else
        raise ArgumentError, "неизвестное противодействие: #{type}"
      end
    end

    def move!(miles)
      raise RuleViolation, 'the car cannot move' unless moving?
      raise RuleViolation, 'speed limit: only 25 or 50 miles allowed' if speed_limited? && miles > 50

      @distance = reversed? ? [@distance - miles, 0].max : @distance + miles
    end

    # съедает один из накопленных пропусков хода, возвращает true,
    # если этот ход был пропущен
    def consume_skip_turn!
      return false if @skip_turns <= 0

      @skip_turns -= 1
      true
    end

    class RuleViolation < StandardError; end
  end
end
