=begin Elten3AppInfo
{
  "id": "ce5cff0e-6a9e-43da-afb3-d050b0ffc4ae",
  "name": "MileByMile",
  "version": "0.4.2",
  "build_id": 7,
  "EltenAPIVersion": "3.0",
  "author": "denizsincar29",
  "main_class": "ProgramMileByMile",
  "platforms": ["all"],
  "description": "Настольная игра «Миля за милей» (Mille Bornes) с ботом-соперником"
}
=end Elten3AppInfo

require_relative "lib/mile_by_mile/card"
require_relative "lib/mile_by_mile/cards/distance_card"
require_relative "lib/mile_by_mile/cards/hazard_card"
require_relative "lib/mile_by_mile/cards/remedy_card"
require_relative "lib/mile_by_mile/cards/safety_card"
require_relative "lib/mile_by_mile/cards/remove_all_safeties_card"
require_relative "lib/mile_by_mile/car"
require_relative "lib/mile_by_mile/deck"
require_relative "lib/mile_by_mile/player"
require_relative "lib/mile_by_mile/team"
require_relative "lib/mile_by_mile/game"
require_relative "lib/mile_by_mile/variants/horse_deck"
require_relative "lib/mile_by_mile_elten/bot"
require_relative "lib/mile_by_mile_elten/audio"
require_relative "lib/mile_by_mile_elten/ui"

class ProgramMileByMile < Program
  def main
    @ui = MileByMileElten::UI.new(self)
    @ui.main
  ensure
    finish
  end
end
