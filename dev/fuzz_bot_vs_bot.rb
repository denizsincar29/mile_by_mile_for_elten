# frozen_string_literal: true

require_relative '../lib/mile_by_mile'
require_relative '../src/lib/mile_by_mile_elten/bot'

include MileByMile

GAMES = (ARGV[0] || 300).to_i
DISTANCES = [1000, 2000, 3000, 4000, 5000].freeze
DECK_MODES = %i[shared separate].freeze
DECK_COPIES = [1, 2, 3, 4, 5].freeze
crashes = 0

GAMES.times do |i|
  distance = DISTANCES.sample
  deck_mode = DECK_MODES[i.even? ? 0 : 1]
  deck_copies = deck_mode == :separate ? 1 : DECK_COPIES[i % DECK_COPIES.size]
  p1 = Player.new('Bot1')
  p2 = Player.new('Bot2')
  game = Game.new([p1, p2], distance_target: distance, deck_mode: deck_mode, deck_copies: deck_copies)
  bot1 = MileByMileElten::Bot.new(game, p1)
  bot2 = MileByMileElten::Bot.new(game, p2)

  turns = 0
  begin
    until game.finished?
      turns += 1
      raise 'infinite game' if turns > 5000

      current = game.current_player
      bot = current.equal?(p1) ? bot1 : bot2
      card, target = bot.choose_move
      break if card.nil? # hand and deck are both empty

      game.play(card, target: target)
    end
  rescue StandardError => e
    crashes += 1
    puts "GAME ##{i} (distance=#{distance}, deck_mode=#{deck_mode}, copies=#{deck_copies}) CRASHED: #{e.class}: #{e.message}"
    puts e.backtrace.first(5)
  end
end

puts "Done: #{GAMES} bot-vs-bot games across distances #{DISTANCES.join('/')}, deck modes #{DECK_MODES.join('/')} and #{DECK_COPIES.join('/')} shared copies, crashes: #{crashes}"
exit(crashes.zero? ? 0 : 1)
