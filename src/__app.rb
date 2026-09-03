# encoding: utf-8
=begin Elten3AppInfo
{
  "id": "ce5cff0e-6a9e-43da-afb3-d050b0ffc4ae",
  "name": "MileByMile",
  "version": "0.4.8",
  "build_id": 13,
  "EltenAPIVersion": "3.0",
  "author": "denizsincar29",
  "main_language": "en",
  "supported_languages": ["en", "de", "es", "fr", "it", "pl", "pt", "ru", "tr", "uk"],
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

  # Ники и строки из уведомлений приходят в ASCII-8BIT. Приводим к UTF-8, чтобы
  # интерполяция с переводами (не-ASCII) не падала Encoding::CompatibilityError.
  def self.utf8(value)
    s = value.to_s.dup
    s.force_encoding(Encoding::UTF_8)
    s.valid_encoding? ? s : s.scrub('')
  end

  # Презентация уведомления приложения в центре уведомлений Elten.
  def self.map_notification(notification)
    return nil unless notification.type == 'game.invite'

    notification.presentation(
      title: _('%{nick} invites you to Mile by Mile') % { nick: utf8(notification.sender) },
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
      m = {}
      metadata.each { |k, v| m[utf8(k)] = utf8(v) }
      variant = m['variant'].to_s == 'horses' ? _('On horses') : _('On cars')
      distance = _('%{d} miles') % { d: (m['distance'] || 1000).to_i }
      deck =
        if m['deck_mode'].to_s == 'separate'
          _('Each player has their own deck')
        else
          _(DECK_LABELS.fetch((m['deck_copies'] || 1).to_i, '1 common deck'))
        end
      "#{variant}, #{distance}, #{deck}"
    end
  end
end
