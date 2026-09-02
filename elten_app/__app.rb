=begin Elten3AppInfo
{
  "id": "ce5cff0e-6a9e-43da-afb3-d050b0ffc4ae",
  "name": "MileByMile",
  "version": "0.4.3",
  "build_id": 8,
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
  # Server application (Elten 3.0.2): единый для всех инсталляций app-id.
  # Уведомления game.invite падают в центр уведомлений Elten, даже когда
  # игра не открыта; клик по уведомлению открывает Mile, где входящий инвайт
  # уже ждёт в @inbox главного цикла.
  server_app(uuid: 'ce5cff0e-6a9e-43da-afb3-d050b0ffc4ae', notifications: true)

  def main
    @ui = MileByMileElten::UI.new(self)
    @ui.main
  ensure
    finish
  end

  # Презентация уведомления приложения в центре уведомлений Elten.
  def self.map_notification(notification)
    return nil unless notification.type == 'game.invite'

    notification.presentation(
      title: _('%{nick} invites you to Mile by Mile') % { nick: notification.sender.to_s },
      body: invite_settings_text(notification.metadata),
      sound: 'notification',
      action: :open_game
    )
  end

  # Клик по уведомлению инвайта: открываем Mile — приглашение само всплывёт
  # в главном меню (endpoint слушает весь срок работы программы).
  def notification_action(action, notification)
    action == :open_game
  end

  class << self
    DECK_LABELS = {
      1 => '1 common deck',
      2 => '2 common decks',
      3 => '3 common decks',
      4 => '4 common decks',
      5 => '5 common decks'
    }.freeze

    def invite_settings_text(metadata)
      metadata ||= {}
      variant = metadata['variant'].to_s == 'horses' ? _('On horses') : _('On cars')
      distance = _('%{d} miles') % { d: (metadata['distance'] || 1000).to_i }
      deck =
        if metadata['deck_mode'].to_s == 'separate'
          _('Each player has their own deck')
        else
          _(DECK_LABELS.fetch((metadata['deck_copies'] || 1).to_i, '1 common deck'))
        end
      "#{variant}, #{distance}, #{deck}"
    end
  end
end
