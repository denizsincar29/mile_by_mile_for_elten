# frozen_string_literal: true

module MileByMileElten
  # Обёртка над play_app_sound. Ассеты лежат плоско в elten_app/audio/
  # (Elten грузит только верхний уровень папки Audio, без подпапок — см.
  # collect_physical_sound_assets/add_sound_asset в elten3, оба используют
  # File.basename без директории как ключ поиска). Поэтому все файлы
  # переименованы в плоские уникальные имена по схеме:
  #   <variant>_<25|50|75|100|200>   — озвучка карт движения
  #   <variant>_welcome              — начало партии (на лошадях тише)
  #   <variant>_bibip                — гудок через 3 сек после старта
  #   <variant>_fail_<key>           — вредительство применилось к цели
  #   <variant>_success_<key>        — противодействие сработало
  #   prot_<key>                     — защита выставлена (тихо, общая)
  #   wow                            — обгон соперника по дистанции
  #   victory / defeat               — финиш первым / проигрыш (общие)
  # variant: cars | horses
  # key:     ready(stall) tank(empty_tank) tire(flat_tire) wheel(turned_back)
  #          seat(accident) speed(speed_limit) pass(skip_turn)
  #
  # Звуки воспроизводятся как в оригинальной ушной игре (Pascal): звучат
  # только реальные переходы состояния — карта, ушедшая в отбой, молчит.
  class Audio
    include MileByMile

    SOUND_KEY = {
      stall: 'ready',
      empty_tank: 'tank',
      flat_tire: 'tire',
      turned_back: 'wheel',
      accident: 'seat',
      speed_limit: 'speed',
      skip_turn: 'pass'
    }.freeze

    # Как в ухе: защиты (prots) и ограничение скорости звучат тише.
    PROT_VOLUME = 40
    SPEED_VOLUME = 40

    attr_accessor :variant

    def initialize(program, variant: :cars)
      @program = program
      @variant = variant
    end

    def play(name, volume: 100, pan: 50, pitch: 100)
      return false if name.nil?

      @program.play_app_sound(name.to_s, volume: volume, pan: pan, pitch: pitch)
    rescue Exception => e
      Log.warning("MileByMile sound #{name} failed: #{e.class}: #{e.message}") if defined?(Log)
      false
    end

    # Начало партии — как в ухе: welcome (на лошадях заметно тише) и гудок
    # через 3 секунды. Звук тасования (cards/shuffle/4.ogg) не воспроизводим —
    # в ассетах его нет.
    def welcome
      play("#{@variant}_welcome", volume: @variant == :horses ? 10 : 100)
      Thread.new do
        sleep 3
        play("#{@variant}_bibip")
      end
    end

    # Карта движения сыграна успешно: номинал + панорама по направлению,
    # при обгоне соперника — дополнительно wow (как в ухе).
    def distance(card, backward: false, overtook: false)
      play("#{@variant}_#{card.miles}", pan: backward ? 30 : 70)
      play('wow') if overtook
    end

    # Вредительство применилось к цели: fail/<n>. Если под раздачу попал и
    # мотор (слив бензина/прокол/авария на едущей машине) — ещё и fail/ready.
    def hazard(card, also_stalled: false)
      key = SOUND_KEY.fetch(card.type, 'ready')
      play("#{@variant}_fail_#{key}", volume: card.type == :speed_limit ? SPEED_VOLUME : 100)
      play("#{@variant}_fail_ready") if also_stalled
    end

    # Противодействие сработало: success/<n>.
    def remedy(card)
      key = SOUND_KEY.fetch(card.cures, 'ready')
      play("#{@variant}_success_#{key}", volume: card.cures == :speed_limit ? SPEED_VOLUME : 100)
    end

    # «Пропуск хода» применён — в ухе это карта успеха (success/pass).
    def skip_turn_applied
      play("#{@variant}_success_pass")
    end

    # Защита выставлена впервые: prots/<n>, тихо.
    def protection(card)
      play("prot_#{SOUND_KEY.fetch(card.type, 'ready')}", volume: PROT_VOLUME)
    end

    # Защита не легла (такая уже стоит) либо у соперника сняты защиты:
    # в ухе это звук fail/pass.
    def protection_wasted
      play("#{@variant}_fail_pass")
    end

    def removed_all_safeties
      play("#{@variant}_fail_pass")
    end

    # Финиш первым (победа) и финиш соперника (поражение) — общие для обоих
    # вариантов звуки victory/defeat (выбор Дениза: 8-bit фанфара и sad
    # trombone; CC BY — атрибуция в AUDIO_ATTRIBUTION.md у корня игры).
    def win
      play('victory')
    end

    def lose
      play('defeat')
    end
  end
end
