# frozen_string_literal: true

module MileByMile
  # Команда: несколько игроков управляют общей машиной.
  # У каждого игрока своя рука карт, но состояние машины одно на всех.
  class Team
    attr_reader :name, :players, :car

    def initialize(name, player_names)
      @name = name
      @car = Car.new
      @players = player_names.map { |n| Player.new(n, car: @car) }
    end

    def to_s
      name
    end
  end
end
