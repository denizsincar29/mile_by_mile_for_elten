# encoding: utf-8
# frozen_string_literal: true

require 'json'

module MileByMileElten
  class UI
    include MileByMile

    DISTANCE_OPTIONS = [1000, 2000, 3000, 4000, 5000].freeze
    VARIANTS = [
      [:cars, 'On cars'],
      [:horses, 'On horses']
    ].freeze
    # Количество общих колод: N полных колод, перемешанных вместе.
    DECK_COPY_COUNTS = [1, 2, 3, 4, 5].freeze
    DECK_LABELS = {
      1 => '1 common deck',
      2 => '2 common decks',
      3 => '3 common decks',
      4 => '4 common decks',
      5 => '5 common decks'
    }.freeze
    # Индекс «3 общие колоды» в списке [своя у каждого, 1..5 общих].
    DEFAULT_DECK_INDEX = 3

    # Последние выбранные настройки партии хранятся в data-json программы:
    # при следующем запуске форма подставляется с ними.
    SETTINGS_FILE = 'settings.json'.freeze

    # Хоткеи игры — Ctrl+M (последний ход) и Ctrl+S (статус). Функциональные
    # клавиши в Элтене заняты: F1-F11/F13-F23 — Quick Actions, F12 —
    # перезапуск клиента. Цифры не берём: в списке карт они работают как
    # быстрый поиск по первой букве («50 миль» на '5'). VK-код распознаётся
    # независимо от раскладки; без Ctrl буквы ничего не делают.
    KEY_LAST_MOVE = 0x4D # M
    KEY_STATUS = 0x53    # S

    IMMOBILIZING = %i[stall empty_tank flat_tire accident].freeze

    # msgid-ключи противодействий по (набор карт, кто, тип карты) — фразы
    # как в ушной игре: на машинах «завести мотор», на лошадях «оседлать».
    REMEDY_KEYS = {
      cars: {
        me: {
          start: 'You started the engine.',
          refuel: 'You refueled.',
          repair_tire: 'You fixed the tire.',
          repair: 'You repaired the car.',
          turn_forward: 'You turned forward.',
          remove_speed_limit: 'You removed the speed limit.'
        },
        bot: {
          start: 'The bot started the engine.',
          refuel: 'The bot refueled.',
          repair_tire: 'The bot fixed the tire.',
          repair: 'The bot repaired the car.',
          turn_forward: 'The bot turned forward.',
          remove_speed_limit: 'The bot removed the speed limit.'
        }
      },
      horses: {
        me: {
          start: 'You saddled up.',
          refuel: 'You fed the horse.',
          repair_tire: 'You shod the horse.',
          repair: 'You let the horse rest.',
          turn_forward: 'You turned forward.',
          remove_speed_limit: 'You removed the speed limit.'
        },
        bot: {
          start: 'The bot saddled up.',
          refuel: 'The bot fed the horse.',
          repair_tire: 'The bot shod the horse.',
          repair: 'The bot let the horse rest.',
          turn_forward: 'The bot turned forward.',
          remove_speed_limit: 'The bot removed the speed limit.'
        }
      }
    }.freeze

    # Фразы защит на лошадях: у седла/голода/подковы/усталости своя
    # конструкция («защитил лошадь от ...»), остальное как на машинах.
    PROTECTION_KEYS = {
      me: {
        stall: 'You protected yourself from falling from the saddle.',
        empty_tank: 'You protected your horse from hunger.',
        flat_tire: 'You protected your horse from losing its horseshoe.',
        accident: 'You protected your horse from exhaustion.',
        turned_back: 'You protected yourself from being turned back.',
        speed_limit: 'You protected yourself from the speed limit.',
        skip_turn: 'You protected yourself from skipping a turn.'
      },
      bot: {
        stall: 'The bot protected itself from falling from the saddle.',
        empty_tank: 'The bot protected its horse from hunger.',
        flat_tire: 'The bot protected its horse from losing its horseshoe.',
        accident: 'The bot protected its horse from exhaustion.',
        turned_back: 'The bot protected itself from being turned back.',
        speed_limit: 'The bot protected itself from the speed limit.',
        skip_turn: 'The bot protected itself from skipping a turn.'
      }
    }.freeze

    # Вредительство озвучивается от имени того, на кого оно легло, как в ухе:
    # «Вы были остановлены» / «Бот был остановлен», а не «Вы заглушили мотор боту».
    HAZARD_KEYS = {
      cars: {
        me: {
          stall: 'You were stopped.',
          empty_tank: 'You ran out of fuel.',
          flat_tire: 'You must pump up your tire.',
          accident: 'You had an accident.',
          turned_back: 'You were turned back.',
          speed_limit: 'You were speed-limited.',
          skip_turn: 'You skip a turn.'
        },
        bot: {
          stall: 'The bot was stopped.',
          empty_tank: 'The bot ran out of fuel.',
          flat_tire: 'The bot must pump up its tire.',
          accident: 'The bot had an accident.',
          turned_back: 'The bot was turned back.',
          speed_limit: 'The bot was speed-limited.',
          skip_turn: 'The bot skips a turn.'
        }
      },
      horses: {
        me: {
          stall: 'You fell from the saddle.',
          empty_tank: 'You must feed your horse.',
          flat_tire: 'You must shoe your horse.',
          accident: 'You must give your horse a rest.',
          turned_back: 'You were turned back.',
          speed_limit: 'You were speed-limited.',
          skip_turn: 'You skip a turn.'
        },
        bot: {
          stall: 'The bot fell from the saddle.',
          empty_tank: 'The bot must feed its horse.',
          flat_tire: 'The bot must shoe its horse.',
          accident: 'The bot must give its horse a rest.',
          turned_back: 'The bot was turned back.',
          speed_limit: 'The bot was speed-limited.',
          skip_turn: 'The bot skips a turn.'
        }
      }
    }.freeze

    REMOVE_ALL_KEYS = {
      me: 'You lost all your protections.',
      bot: 'The bot lost all its protections.'
    }.freeze

    def initialize(program)
      @program = program
      @audio = Audio.new(program)
      # очередь входящих событий мультиплеера [kind, payload]; события кладут
      # колбэки EltenAPI::Communication, а хендлеры разбирают их в Runner-циклах
      @inbox = []
      @multiplayer = false
    end

    # Плоское главное меню: без подменю, мультиплеер открыт со старта.
    # Слушатель приглашений висит весь срок программы — входящее приглашение
    # от друга показывается между выборами меню, отдельный «режим ожидания»
    # не нужен.
    def main
      register_invitation_listener
      loop do
        if (invitation = take_pending_invitation)
          play_invited_game(invitation)
          next
        end
        index = selector(
          [_('Create a game'), _('Join a game'), _('Invite a friend'), _('Play against the bot'), _('Rules'), _('Exit')],
          header: _('Mile by Mile'),
          start_index: 0,
          cancel_index: 5
        )
        case index
        when 0 then create_public_game
        when 1 then join_public_game
        when 2 then invite_friend
        when 3 then play_vs_bot
        when 4 then show_help
        else break
        end
      end
    end

    private

    # Elten's gettext reads .mo strings as ASCII-8BIT; re-tag to UTF-8 so
    # join/% with UTF-8 literals don't raise Encoding::CompatibilityError.
    def _(msgid)
      super(msgid).dup.force_encoding(Encoding::UTF_8)
    end

    def play_vs_bot
      settings = choose_settings
      return if settings.nil?

      variant, distance, deck_mode, deck_copies = settings

      @audio.variant = variant
      @variant = variant
      deck_class = variant == :horses ? Variants::HorseDeck : Deck

      @human = Player.new(_('You'))
      @bot_player = Player.new(_('Bot'))
      @game = Game.new([@human, @bot_player], distance_target: distance, deck_class: deck_class, deck_mode: deck_mode, deck_copies: deck_copies)
      @bot = Bot.new(@game, @bot_player)

      @move_history = []

      @audio.welcome
      alert(start_announcement, false)
      return if play_rounds == :aborted

      announce_result
    end

    # Настройки одной формой: три переключателя (набор карт, дистанция,
    # количество колод) и кнопки ОК/Отмена. Позиции подставляются из
    # сохранённых последних настроек (data-json программы). Возвращает
    # [variant, distance, deck_mode, deck_copies] или nil.
    def choose_settings
      last = load_last_settings
      variant_labels = VARIANTS.map { |_id, label| _(label) }
      distance_labels = DISTANCE_OPTIONS.map { |d| _('%{d} miles') % { d: d } }
      deck_labels = [_('Each player has their own deck')]
      DECK_COPY_COUNTS.each { |n| deck_labels << _(DECK_LABELS[n]) }

      # Метка строки пустая: иначе ChoiceListBox озвучивает «метка: значение»,
      # и при фокусе метка дублируется (header звучит отдельно) — «дистанция,
      # дистанция, 1000 миль». С пустой меткой при фокусе слышно «Дистанция:
      # 1000 миль», а при смене значения — только само значение.
      fields = [
        ChoiceListBox.new([['', variant_labels, last[:variant_index]]], header: _('Card set')),
        ChoiceListBox.new([['', distance_labels, last[:distance_index]]], header: _('Distance')),
        ChoiceListBox.new([['', deck_labels, last[:deck_index]]], header: _('Number of decks'))
      ]
      accept = Button.new(_('OK'))
      cancel = Button.new(_('Cancel'))
      fields << accept << cancel
      form = Form.new(fields, index: 0)
      form.accept_button = accept
      form.cancel_button = cancel
      confirmed = false
      accept.on(:press) { confirmed = true; form.resume }
      cancel.on(:press) { form.resume }
      form.wait
      return nil unless confirmed

      variant = VARIANTS[fields[0].value(0)][0]
      distance = DISTANCE_OPTIONS[fields[1].value(0)]
      deck_idx = fields[2].value(0)
      deck_mode = deck_idx.zero? ? :separate : :shared
      deck_copies = [deck_idx, 1].max
      settings = [variant, distance, deck_mode, deck_copies]
      save_last_settings(settings)
      settings
    end

    # Чтение последних настроек из data-json. Индексы вычисляются так, чтобы
    # форма открылась с прошлыми значениями; на битые данные — дефолты.
    def load_last_settings
      saved = @program.read_json(SETTINGS_FILE, default: {})
      saved = {} unless saved.is_a?(Hash)
      last = saved['last'].is_a?(Hash) ? saved['last'] : {}
      variant = (last['variant'] || 'cars').to_sym
      distance = (last['distance'] || 1000).to_i
      deck_mode = (last['deck_mode'] || 'shared').to_sym
      deck_copies = (last['deck_copies'] || DECK_COPY_COUNTS[DEFAULT_DECK_INDEX - 1]).to_i

      variant_index = VARIANTS.index { |id, _label| id == variant } || 0
      distance_index = DISTANCE_OPTIONS.index(distance) || 0
      deck_index =
        if deck_mode == :separate
          0
        else
          i = DECK_COPY_COUNTS.index(deck_copies)
          i ? i + 1 : DEFAULT_DECK_INDEX
        end
      { variant_index: variant_index, distance_index: distance_index, deck_index: deck_index }
    end

    # Последние настройки — в data-json программы. Ошибка записи не роняет
    # запуск партии: молча пропускаем (нет диска — играем всё равно).
    def save_last_settings(settings)
      variant, distance, deck_mode, deck_copies = settings
      @program.write_json(SETTINGS_FILE, 'last' => {
                            'variant' => variant.to_s,
                            'distance' => distance,
                            'deck_mode' => deck_mode.to_s,
                            'deck_copies' => deck_copies
                          })
    rescue StandardError
      nil
    end

    # Стартовый анонс: «Поехали! По воле судьбы первым ходите вы / ходит бот.»,
    # а для человека ещё и седьмая карта, которую он добирает в начале хода.
    def start_announcement
      phrase =
        if @game.current_player.equal?(@human)
          _('By fate\'s will, you move first.')
        else
          _('By fate\'s will, the bot moves first.')
        end
      text = "#{_('Let\'s go!')} #{phrase}"
      drawn_seventh = @game.current_player.equal?(@human) ? @human.hand.last : nil
      text += " #{draw_phrase(@human, drawn_seventh)}" if drawn_seventh
      text
    end

    # Основной цикл партии. Возвращает :aborted, если игрок подтвердил выход.
    def play_rounds
      until @game.finished?
        if @game.current_player.equal?(@human)
          return :aborted if human_turn == :aborted
        else
          return :aborted if bot_turn == :aborted
        end
      end
      nil
    end

    # --- мультиплеер ---

    # Лениво создаём endpoint Communication (app_id из манифеста). Колбэки
    # Communication диспатчатся на главном потоке из главного цикла Elten
    # (Communication.tick в loop.rb), поэтому @inbox трогается только из
    # основного потока и мьютекс не нужен. Без сети endpoint не строится —
    # nil; все вызовы поверх него обёрнуты и падают в «Cannot connect».
    def communication_endpoint
      @communication ||= @program.communication
    rescue StandardError
      nil
    end

    # Глобальный приём приглашений: колбэк кладёт Invitation в @inbox, а
    # главный цикл main предлагает его принять между показами меню. Флаг
    # ставится только при успехе, так что при временной потере сети
    # следующий вход в main попробует поднять endpoint снова.
    def register_invitation_listener
      return if @invitation_listener

      endpoint = communication_endpoint
      return unless endpoint

      endpoint.on_invitation do |invitation|
        @inbox << [:invitation, invitation]
      end
      @invitation_listener = true
    rescue StandardError
      nil
    end

    # Подписка сессии на события партии: входящие сообщения, приход и уход
    # участника, закрытие сессии — всё в @inbox для Runner-циклов.
    def register_session_listeners(session)
      session.on_reliable { |msg| @inbox << [:reliable, msg] }
      session.on_participant_joined { |participant| @inbox << [:participant_joined, participant] }
      session.on_participant_left { |participant, _reason| @inbox << [:participant_left, participant] }
      session.on_closed { |reason| @inbox << [:session_closed, reason] }
    end

    # Настройки партии уходят гостю через session_metadata сессии — JSON.
    def settings_payload(variant, distance, deck_mode, deck_copies)
      { 'variant' => variant.to_s, 'distance_target' => distance,
        'deck_mode' => deck_mode.to_s, 'deck_copies' => deck_copies }
    end

    def parse_settings(settings)
      settings ||= {}
      variant = (settings['variant'] || 'cars').to_sym
      distance = (settings['distance_target'] || 1000).to_i
      deck_mode = (settings['deck_mode'] || 'shared').to_sym
      deck_copies = (settings['deck_copies'] || 1).to_i
      [variant, distance, deck_mode, deck_copies]
    end

    def parse_packet(data)
      JSON.parse(data.to_s.dup.force_encoding(Encoding::UTF_8))
    rescue JSON::ParserError, TypeError
      nil
    end

    # Ники и строки из Communication API приходят в ASCII-8BIT. Приводим к
    # UTF-8, чтобы конкатенация с переводами (не-ASCII) не падала
    # Encoding::CompatibilityError.
    def utf8(value)
      s = value.to_s.dup
      s.force_encoding(Encoding::UTF_8)
      s.valid_encoding? ? s : s.scrub('')
    end

    def packet_type(data)
      pkt = parse_packet(data)
      pkt && pkt['type']
    end

    # Ожидание нужного события в Runner: Ctrl+M/Ctrl+S активны, Escape — отмена,
    # timeout секунд — выход по таймауту. Блок получает событие [kind,
    # payload] и возвращает true, когда событие «наше». Найденное событие
    # удаляется из очереди, чтобы не перехватывалось повторно. Возвращает
    # [kind, payload], :timeout или :cancelled.
    def wait_for_events(timeout: 60, cancel_text: _('Cancel waiting?'))
      runner = Runner.new
      bind_game_hotkeys(runner)
      runner.on_key(:key_escape) { |current| current.stop(:cancelled) if confirm(cancel_text) }
      runner.after(timeout) { |current| current.stop(:timeout) }
      found = nil
      runner.on_tick do |current|
        i = @inbox.index { |event| yield(event) }
        next unless i

        found = @inbox.delete_at(i)
        current.stop
      end
      runner.run
      found
    end

    # Завершение сессии партии: хост закрывает её для всех, гость просто
    # покидает. Идемпотентно — безопасно звать из любого места выхода.
    def teardown_session
      session = @session
      @session = nil
      return unless session

      if @mp_host
        session.close
      else
        session.leave
      end
    rescue StandardError
      nil
    end

    # Вынуть из @inbox первое входящее приглашение, если оно там есть. Зовётся
    # из главного цикла между показами меню — приглашение от друга
    # всплывает, даже когда игрок не сидит в «режиме ожидания».
    def take_pending_invitation
      i = @inbox.index { |kind, _| kind == :invitation }
      i && @inbox.delete_at(i)[1]
    end

    # Ник владельца (хоста) публичной сессии — создатель помечен owner?.
    def public_session_host(public_session)
      host = public_session.participants.find(&:owner?)
      host = public_session.participants.first if host.nil?
      utf8(host&.user)
    end

    # Описание публичной сессии для списка «Join a game»: хост + настройки.
    def public_session_label(public_session)
      host = public_session_host(public_session)
      host = _('Unknown player') if host.to_s.empty?
      variant, distance, deck_mode, deck_copies = parse_settings(public_session.metadata)
      "#{host} — #{describe_settings(variant, distance, deck_mode, deck_copies)}"
    end

    # Хост лобби: выбрать настройки → открыть публичную игру → ждать, пока
    # кто-то присоединится из «Join a game» → собрать партию и стартовать.
    def create_public_game
      settings = choose_settings
      return if settings.nil?

      variant, distance, deck_mode, deck_copies = settings
      session =
        begin
          communication_endpoint.create_session(
            metadata: settings_payload(variant, distance, deck_mode, deck_copies),
            capacity: 2,
            public: true
          )
        rescue StandardError
          alert(_('Cannot connect to the multiplayer server.'), false)
          return
        end
      @session = session
      @mp_host = true
      register_session_listeners(session)

      alert(_('The game is open in the lobby. Waiting for an opponent. Escape — cancel.'), false)
      status = nil
      runner = Runner.new
      bind_game_hotkeys(runner)
      runner.on_key(:key_escape) { |current| current.stop(:cancelled) if confirm(_('Cancel waiting for an opponent?')) }
      runner.after(120) { |current| current.stop(:timeout) }
      runner.on_tick do |current|
        if session.participants.size >= 2
          status = :ready
          current.stop
        elsif @inbox.any? { |kind, _| kind == :session_closed }
          status = :closed
          current.stop
        end
      end
      status = runner.run || status

      if status == :ready
        guest = session.participants.find { |p| !p.owner? }
        guest_nick = utf8(guest&.user)
        guest_nick = _('Opponent') if guest_nick.empty?
        start_hosted_game(variant, distance, deck_mode, deck_copies, guest_nick)
      else
        alert(_('No one joined the game.'), false)
        teardown_session
      end
    end

    # Гость лобби: свежий список публичных игр → выбрать → войти → дождаться
    # start от хоста → собрать партию.
    def join_public_game
      sessions =
        begin
          communication_endpoint.public_sessions
        rescue StandardError
          alert(_('Cannot connect to the multiplayer server.'), false)
          return
        end
      sessions = sessions.reject(&:full?)
      if sessions.empty?
        alert(_('No games in the lobby yet.'), false)
        return
      end

      index = selector(
        sessions.map { |ps| public_session_label(ps) },
        header: _('Join a game'),
        start_index: 0,
        cancel_index: -1
      )
      return if index.nil? || index.negative?

      ps = sessions[index]
      host_nick = public_session_host(ps)
      host_nick = _('Unknown player') if host_nick.empty?
      variant, distance, deck_mode, deck_copies = parse_settings(ps.metadata)
      session =
        begin
          communication_endpoint.join(ps)
        rescue StandardError
          alert(_('Cannot join the game.'), false)
          return
        end
      @session = session
      @mp_host = false
      register_session_listeners(session)

      join_and_wait_start(host_nick, variant, distance, deck_mode, deck_copies)
    end

    # Хост собрал соперника (из лобби или принявшего инвайт друга): построить
    # движок, послать start с сидом и порядком и прогнать партию.
    def start_hosted_game(variant, distance, deck_mode, deck_copies, opponent_nick)
      seed = rand(2**31)
      @variant = variant
      @audio.variant = variant
      @multiplayer = true
      @human = Player.new(_('You'))
      @opponent = Player.new(opponent_nick)
      @game = build_mp_game([@human, @opponent], variant, distance, deck_mode, deck_copies, seed)
      @move_history = []

      send_mp_json('type' => 'start', 'seed' => seed, 'first' => @game.current_index)

      @audio.welcome
      alert(start_announcement_mp, false)
      finish_mp_rounds
      @multiplayer = false
      :played
    end

    # Пригласить конкретного друга по нику: приватная сессия и инвайт; если
    # программа объявила серверное приложение — друг ещё и получает
    # уведомление в Элтен. Пока друг не принял, инвайт повторяется: он мог
    # открыть Mile только после уведомления, а инвайт доходит лишь когда его
    # endpoint активен.
    def invite_friend
      nick = input_text(_('Friend nickname'), escapable: true, text: '')
      return if nick.nil? || nick.strip.empty?

      nick = nick.strip
      card = user_card(nick)
      if card.nil?
        alert(_('Cannot verify the user. Check the connection.'), false)
        return
      end
      if card.name.to_s.empty?
        alert(_('There is no user with this name.'), false)
        return
      end
      unless card.status.online
        return unless confirm(_('The user is offline. Send the invitation anyway?'))
      end

      settings = choose_settings
      return if settings.nil?

      variant, distance, deck_mode, deck_copies = settings
      session =
        begin
          communication_endpoint.create_session(
            metadata: settings_payload(variant, distance, deck_mode, deck_copies),
            capacity: 2
          )
        rescue StandardError
          alert(_('Cannot connect to the multiplayer server.'), false)
          return
        end
      @session = session
      @mp_host = true
      register_session_listeners(session)

      begin
        session.invite(nick)
      rescue StandardError
        alert(_('Cannot invite %{nick}.') % { nick: nick }, false)
        teardown_session
        return
      end
      send_invite_notification(nick, variant, distance, deck_mode, deck_copies)

      status = nil
      last_retry = Time.now.to_f
      runner = Runner.new
      bind_game_hotkeys(runner)
      runner.on_key(:key_escape) { |current| current.stop(:cancelled) if confirm(_('Cancel waiting?')) }
      runner.after(180) { |current| current.stop(:timeout) }
      runner.on_tick do |current|
        if session.participants.size >= 2
          status = :accepted
          current.stop
        elsif @inbox.any? { |kind, _| kind == :session_closed }
          status = :cancelled
          current.stop
        elsif Time.now.to_f - last_retry >= 8
          last_retry = Time.now.to_f
          begin
            session.invite(nick)
          rescue StandardError
            nil
          end
        end
      end
      status = runner.run || status
      case status
      when :accepted
        start_hosted_game(variant, distance, deck_mode, deck_copies, nick)
      else
        alert(_('No response from %{nick}.') % { nick: nick }, false)
        teardown_session
      end
    end

    # Входящее приглашение от друга, пойманное в главном меню: принять или
    # отклонить, войти в сессию хоста и сыграть. Отдельного «режима ожидания»
    # больше нет — меню приём приглашений держит само.
    def play_invited_game(invitation)
      host_nick = utf8(invitation.sender.user)
      variant, distance, deck_mode, deck_copies = parse_settings(invitation.session_metadata)

      invite_text = (_('%{nick} invites you: %{settings}. Accept?') %
                     { nick: host_nick, settings: describe_settings(variant, distance, deck_mode, deck_copies) })
      unless confirm(invite_text)
        invitation.reject
        return
      end

      session =
        begin
          invitation.accept
        rescue StandardError
          alert(_('Cannot accept the invitation.'), false)
          return
        end
      @session = session
      @mp_host = false
      register_session_listeners(session)

      join_and_wait_start(host_nick, variant, distance, deck_mode, deck_copies)
    end

    # Гость уже в сессии (принял инвайт или влился в лобби): дождаться start
    # от хоста, собрать движок в том же порядке (хост, гость), сверить
    # синхронизацию и прогнать партию.
    def join_and_wait_start(host_nick, variant, distance, deck_mode, deck_copies)
      start_res = wait_for_events(timeout: 60, cancel_text: _('Cancel waiting for the start?')) do |kind, payload|
        kind == :reliable && packet_type(payload.data) == 'start'
      end
      if start_res.nil? || start_res == :timeout || start_res == :cancelled
        teardown_session
        return :cancelled
      end

      start = parse_packet(start_res[1].data)
      if start.nil?
        teardown_session
        return :cancelled
      end

      seed = start['seed'] || rand(2**31)
      @variant = variant
      @audio.variant = variant
      @multiplayer = true
      @human = Player.new(_('You'))
      @opponent = Player.new(host_nick)
      @game = build_mp_game([@opponent, @human], variant, distance, deck_mode, deck_copies, seed)
      @move_history = []

      unless @game.current_index == start['first']
        alert(_('The game is out of sync. Return to the menu.'), false)
        @multiplayer = false
        teardown_session
        return :cancelled
      end

      @audio.welcome
      alert(start_announcement_mp, false)
      finish_mp_rounds
      @multiplayer = false
      :played
    end

    # Уведомление другу в Элтен через серверное приложение программы.
    # Работает только когда server_app объявлен, зарегистрирован и включает
    # notifications — иначе базовый канал (Communication-инвайт) остаётся.
    def send_invite_notification(nick, variant, distance, deck_mode, deck_copies)
      definition = @program.respond_to?(:server_app_definition) ? @program.server_app_definition : nil
      return unless definition && definition.uuid && definition.notifications?

      @program.send_notification(
        nick,
        type: 'game.invite',
        metadata: {
          'variant' => variant.to_s,
          'distance' => distance,
          'deck_mode' => deck_mode.to_s,
          'deck_copies' => deck_copies
        },
        expires_in: 600
      )
    rescue StandardError
      nil
    end

    def build_mp_game(players, variant, distance, deck_mode, deck_copies, seed)
      deck_class = variant == :horses ? Variants::HorseDeck : Deck
      Game.new(players, distance_target: distance, deck_class: deck_class,
                        deck_mode: deck_mode, deck_copies: deck_copies, seed: seed)
    end

    def describe_settings(variant, distance, deck_mode, deck_copies)
      parts = []
      parts << (variant == :horses ? _('On horses') : _('On cars'))
      parts << (_('%{d} miles') % { d: distance })
      parts << (deck_mode == :separate ? _('Each player has their own deck') : _(DECK_LABELS[deck_copies]))
      parts.join(', ')
    end

    def start_announcement_mp
      if @game.current_player.equal?(@human)
        _('By fate\'s will, you move first.')
      else
        (_('By fate\'s will, %{nick} moves first.') % { nick: @opponent.name })
      end
    end

    # Цикл партии мультиплеера: ходит тот, кому по движку принадлежит ход.
    # :aborted — игрок вышел (Escape, таймаут, соперник ушёл). Сессия
    # закрывается в любом случае: на выходе — bye + закрытие, на финише —
    # просто закрытие.
    def finish_mp_rounds
      aborted = false
      until @game.finished?
        if @game.current_player.equal?(@human)
          aborted = true if mp_human_turn == :aborted
        else
          aborted = true if mp_opponent_turn == :aborted
        end
        break if aborted
      end
      if aborted
        send_mp_bye
        alert(_('The game is over.'), true)
      else
        announce_mp_result
      end
      teardown_session
    end

    # Ход игрока в мультиплеере: как human_turn, но ход уходит сопернику.
    def mp_human_turn
      @pick_cursor = nil
      loop do
        return nil if @human.hand.empty?

        card = pick_card
        return :aborted if card == :aborted

        target = card.opponent_only? ? @opponent : nil
        before = @human.hand.dup
        idx = before.index(card)
        ctx = play_context(@human, target)
        begin
          result = @game.play(card, target: target)
        rescue MileByMile::Game::RuleViolation => e
          alert(e.message, false)
          next
        end

        send_mp_move(idx, card)
        play_card_audio(card, result, @human, target, ctx)
        action = record_move(@human, card, target: target, result: result)
        drawn = (@human.hand - before).first
        line = drawn ? "#{action} #{draw_phrase(@human, drawn)}" : action

        if @game.finished?
          alert(action, false)
          return nil
        else
          tail = turn_tail(human_moved: true)
          alert(tail.empty? ? line : "#{line} #{tail}", true)
          return nil unless @game.current_player.equal?(@human)
        end
      end
    end

    # Ход соперника: ждём move, применяем к своему движку, озвучиваем.
    # Выход соперника видим как bye, участник_left или закрытие сессии.
    def mp_opponent_turn
      result = wait_for_events(timeout: 300, cancel_text: _('End the game?')) do |kind, payload|
        case kind
        when :reliable
          type = packet_type(payload.data)
          type == 'move' || type == 'bye'
        when :participant_left, :session_closed
          true
        else
          false
        end
      end
      return :aborted if result.nil? || result == :timeout || result == :cancelled

      kind, payload = result
      case kind
      when :participant_left, :session_closed
        :aborted
      when :reliable
        pkt = parse_packet(payload.data)
        return :aborted if pkt.nil? || pkt['type'] == 'bye'

        apply_opponent_move(pkt)
        nil
      end
    end

    # Применить ход соперника к локальному движку и озвучить, как в ухе.
    def apply_opponent_move(pkt)
      human_before = @human.hand.dup
      opp_dist_before = @opponent.car.distance
      ctx = {
        prev_distance: opp_dist_before,
        target_was_running: @human.car.running?,
        target_safeties: @human.car.safeties.size
      }
      result = @game.apply_move(pkt['card_index'], pkt['target'] == 'opponent' ? :opponent : nil)
      card = @game.discard_pile.last
      target = card.opponent_only? ? @human : nil
      play_card_audio(card, result, @opponent, target, ctx)
      action = record_move(@opponent, card, target: target, result: result)
      drawn = (@human.hand - human_before).first
      line = drawn ? "#{action} #{draw_phrase(@human, drawn)}" : action
      tail = turn_tail(human_moved: false)
      alert(tail.empty? ? line : "#{line} #{tail}", true)
    end

    def send_mp_move(card_index, card)
      target = card.opponent_only? ? 'opponent' : nil
      send_mp_json('type' => 'move', 'card_index' => card_index, 'target' => target)
    end

    def send_mp_bye
      send_mp_json('type' => 'bye')
    end

    # Отправка пакета партии через надёжный канал сессии (JSON). Ошибка
    # отправки не роняет ход: выход соперник увидит по закрытию сессии.
    def send_mp_json(payload)
      @session.send_reliable(JSON.generate(payload))
    rescue StandardError
      nil
    end

    def announce_mp_result
      winner = @game.winner
      if winner.equal?(@human)
        @audio.win
        alert(_('You are at the finish line. Congratulations!'), true)
      elsif winner
        @audio.lose
        alert((_('%{nick} is at the finish line.') % { nick: @opponent.name }), true)
      else
        alert(_('The deck ran out. Draw.'), true)
      end
    end

    def user_card(nick)
      EltenLink::Profiles.card(EltenLink.client(@program), nick)
    rescue StandardError
      nil
    end

    # В мультиплеере у соперника не «бот», а ник: подменяем локализованное
    # «The bot» в готовой фразе на имя игрока.
    def localize_subject(text, player)
      return text unless @multiplayer
      return text if player.equal?(@human)

      text.sub(_('The bot'), player.name)
    end

    # --- ход игрока ---

    def human_turn
      # Новый ход начинается с первой карты; позиция курсора сохраняется
      # только внутри серии ходов подряд (pick_card её запоминает).
      @pick_cursor = nil
      loop do
        return nil if @human.hand.empty?

        card = pick_card
        return :aborted if card == :aborted

        target = card.opponent_only? ? @bot_player : nil
        before = @human.hand.dup
        ctx = play_context(@human, target)
        begin
          result = @game.play(card, target: target)
        rescue MileByMile::Game::RuleViolation => e
          alert(e.message, false)
          next
        end

        play_card_audio(card, result, @human, target, ctx)
        action = record_move(@human, card, target: target, result: result)
        # карта добирается только при удержанном ходе (защита) — озвучиваем
        # тут же; при переходе хода к боту добор придёт в начале хода игрока
        drawn = (@human.hand - before).first
        line = drawn ? "#{action} #{draw_phrase(@human, drawn)}" : action

        if @game.finished?
          alert(action, false)
          return nil
        else
          tail = turn_tail(human_moved: true)
          alert(tail.empty? ? line : "#{line} #{tail}", true)
          return nil unless @game.current_player.equal?(@human)
        end
      end
    end

    # Список карт руки на ListBox внутри Runner: Enter выбирает карту,
    # Ctrl+M/Ctrl+S/Escape активны всё время хода. Возвращает карту или :aborted.
    # Заголовок списка пустой: «Ваш ход» уже сказан хвостом предыдущего анонса
    # (turn_tail) — заголовок дублировал бы его отдельной репликой.
    def pick_card
      loop do
        options = @human.hand.map { |c| _(c.name) }
        header = ''
        picked = nil
        runner = Runner.new
        bind_game_hotkeys(runner)
        runner.on_key(:key_escape) do |current|
          current.stop(:aborted) if confirm(_('End the game?'))
        end
        list = ListBox.new(options, header: header, index: pick_index(options.size), flags: ListBox::Flags::AnyDir, quiet: false)
        mark_playable_cards(list)
        list.on(:select) { |selection| picked = selection[0] }
        runner.on_tick do
          list.update
          runner.stop if picked != nil
        end
        list.focus
        return :aborted if runner.run == :aborted
        next unless picked

        @pick_cursor = picked
        return @human.hand[picked]
      end
    end

    # Стартовая позиция курсора списка карт. Удержанный ход (защита) открывает
    # список снова; чтобы фокус «остался на той же карте», где его оставил игрок,
    # возвращаем позицию последнего выбора, ограниченную размером новой руки.
    def pick_index(size)
      return 0 if @pick_cursor.nil? || size <= 0

      [@pick_cursor, size - 1].min
    end

    # Карты, которые сыграются с эффектом, помечаем статусом строки со звуком
    # «закреплённый элемент списка»: при фокусе на такой карте Elten играет
    # чпуньк (как форумы «пинят» закреплённые темы). Карты-пустышки, которые
    # уйдут в отбой, звука не дают — чтобы не выбросить карту, думая, что она
    # сыграется. Наличие эффекта считает движок (Game#effective?), без мутаций.
    def mark_playable_cards(list)
      return if @game.nil?

      opponent = @multiplayer ? @opponent : @bot_player
      @human.hand.each_with_index do |card, index|
        target = card.opponent_only? ? opponent : nil
        next unless @game.effective?(card, target: target)

        list.set_item_status(index, 'listbox_itempinned', '', '')
      end
    end

    # --- ход бота ---

    def bot_turn
      return :aborted if bot_think == :aborted

      card, target = @bot.choose_move
      return nil if card.nil?

      human_before = @human.hand.dup
      ctx = play_context(@bot_player, target)
      begin
        result = @game.play(card, target: target)
      rescue MileByMile::Game::RuleViolation
        fallback = @bot_player.hand.find { |c| c.is_a?(RemedyCard) || c.is_a?(SafetyCard) }
        return nil unless fallback

        result = @game.play(fallback, target: nil)
        card = fallback
      end

      play_card_audio(card, result, @bot_player, target, ctx)
      # ход бота озвучивается сразу, как событие (wait: блокируем, чтобы
      # «Ваш ход» в следующем списке не перебил его) — как в ухе
      text = record_move(@bot_player, card, target: target, result: result)
      # после хода бота игрок добирает карту для своего хода — в ухе она
      # озвучивается одной фразой перед списком «Ваш ход»
      drawn = (@human.hand - human_before).first
      if drawn && !@game.finished? && @game.current_player.equal?(@human)
        text += " #{draw_phrase(@human, drawn)}"
      end
      tail = turn_tail(human_moved: false)
      alert(tail.empty? ? text : "#{text} #{tail}", true)
      nil
    end

    # Пауза перед ходом бота: рандом 2-4 секунды (сложный выбор — до ~5.5).
    # В это время Ctrl+M/Ctrl+S/Escape активны. Ничего не озвучиваем — сам ход бота
    # проговорится сразу после паузы (как в ухе).
    def bot_think
      runner = Runner.new
      bind_game_hotkeys(runner)
      runner.on_key(:key_escape) do |current|
        current.stop(:aborted) if confirm(_('End the game?'))
      end
      runner.after(@bot.think_duration) { |current| current.stop }
      runner.run == :aborted ? :aborted : nil
    end

    # --- история ходов и статусы ---

    def record_move(player, card, target: nil, result:)
      text = action_phrase(player, card, target: target, result: result)
      text = localize_subject(text, player)
      @move_history << text
      @move_history.shift if @move_history.size > 100
      text
    end

    # Хвост к сообщению о ходе — чей следующий ход. Озвучка одним сообщением:
    # «Вы проехали 200 миль. Ходит бот.» / «Бот защитился. Ходит бот.» /
    # «Бот проехал 50 миль. Ваш ход.» — чтобы «Ваш ход» не звучал отдельной
    # репликой списка сверху. human_moved: только что ходил человек; если он
    # сохранил ход (первая защита), хвост пуст — человек уже смотрит в список
    # карт и повторное «Ваш ход» было бы шумом. А вот повторный ход бота или
    # соперника после защиты озвучивается («Ходит бот» / «Ходит xuser»), как в
    # живом разговоре.
    def turn_tail(human_moved:)
      return '' if @game.nil? || @game.finished?

      if @game.current_player.equal?(@human)
        human_moved ? '' : _('Your turn.')
      elsif @multiplayer
        _('%{nick} moves next.') % { nick: @opponent.name }
      else
        _('The bot moves.')
      end
    end

    # Контекст розыгрыша ДО применения карты — для звука «как в ухе»: звучат
    # только реально сработавшие переходы состояния.
    def play_context(player, target)
      {
        prev_distance: player.car.distance,
        target_was_running: target&.car&.running?,
        target_safeties: target&.car&.safeties&.size
      }
    end

    # Звук по исходу розыгрыша — как в ухе: карта, ушедшая в отбой, молчит
    # (кроме случая, когда защита не легла из-за уже стоящей), движение с
    # обгоном соперника играет wow.
    def play_card_audio(card, result, player, target, ctx)
      case card
      when DistanceCard
        return if result == :wasted

        @audio.distance(card, backward: player.car.reversed?, overtook: overtook?(player, ctx))
      when HazardCard
        return if result == :wasted

        if card.type == :skip_turn
          @audio.skip_turn_applied
        else
          also_stalled = ctx[:target_was_running] && %i[empty_tank flat_tire accident].include?(card.type)
          @audio.hazard(card, also_stalled: also_stalled)
        end
      when RemedyCard
        return if result == :wasted

        @audio.remedy(card)
      when SafetyCard
        result == :kept_turn ? @audio.protection(card) : @audio.protection_wasted
      when RemoveAllSafetiesCard
        @audio.removed_all_safeties if result == :played && ctx[:target_safeties].to_i.positive?
      end
    end

    # Обгон соперника по дистанции — как в ухе, играет wow.
    def overtook?(player, ctx)
      return false if player.car.reversed?

      other = @game.players.find { |p| !p.equal?(player) }
      other && ctx[:prev_distance] <= other.car.distance && player.car.distance > other.car.distance
    end

    # Фраза действия: что сыграл (или сбросил) игрок. Именно её NVDA читает
    # после хода, поэтому она же попадает в историю для Ctrl+M.
    def action_phrase(player, card, target: nil, result:)
      me = player.equal?(@human)
      return discard_phrase(player, card) if result == :wasted

      case card
      when DistanceCard
        distance_phrase(me, player.car.reversed?, card)
      when RemedyCard
        remedy_phrase(me, card.type)
      when SafetyCard
        protection_phrase(me, card.type)
      when HazardCard
        hazard_phrase(me, card.type)
      when RemoveAllSafetiesCard
        remove_all_phrase(me)
      end
    end

    # Набор карт: машины или лошади. Меняет глаголы фраз как в ушной игре.
    def cars?
      @variant != :horses
    end

    def distance_phrase(me, backward, card)
      key =
        if cars?
          backward ? (me ? 'You drove back %{miles}.' : 'The bot drove back %{miles}.')
                   : (me ? 'You drove %{miles}.' : 'The bot drove %{miles}.')
        else
          backward ? (me ? 'You galloped back %{miles}.' : 'The bot galloped back %{miles}.')
                   : (me ? 'You galloped %{miles}.' : 'The bot galloped %{miles}.')
        end
      _(key) % { miles: _(card.name) }
    end

    def remedy_phrase(me, type)
      _(REMEDY_KEYS[@variant || :cars][me ? :me : :bot][type])
    end

    # Защита: на машинах «защитился от ...», на лошадях своя конструкция
    # для седла/голода/подковы/усталости — как в ушной игре.
    def protection_phrase(me, type)
      if cars?
        key = me ? 'You protected yourself from %{hazard}.' : 'The bot protected itself from %{hazard}.'
        _(key) % { hazard: hazard_genitive(type) }
      else
        _(PROTECTION_KEYS[me ? :me : :bot][type])
      end
    end

    # Родительный падеж после «защитился от ...» на машинах — как в ушной игре.
    def hazard_genitive(type)
      case type
      when :stall then _('engine stalling')
      when :empty_tank then _('fuel draining')
      when :flat_tire then _('a flat tire')
      when :accident then _('an accident')
      when :turned_back then _('being turned around')
      when :speed_limit then _('the speed limit')
      when :skip_turn then _('skipping a turn')
      end
    end

    def hazard_phrase(me, type)
      # цель — противоположный игрок: о последствии вредительства говорим
      # от его имени, а не от имени того, кто сыграл карту
      target = me ? :bot : :me
      _(HAZARD_KEYS[@variant || :cars][target][type])
    end

    def remove_all_phrase(me)
      # о снятии защит тоже говорим от имени того, кто их потерял
      _(REMOVE_ALL_KEYS[me ? :bot : :me])
    end

    def draw_phrase(player, card)
      me = player.equal?(@human)
      text = me ? _('You drew %{card}.') % { card: _(card.name) } : _('The bot drew %{card}.') % { card: _(card.name) }
      localize_subject(text, player)
    end

    def discard_phrase(player, card)
      me = player.equal?(@human)
      text = me ? _('You discarded %{card}.') % { card: _(card.name) } : _('The bot discarded %{card}.') % { card: _(card.name) }
      localize_subject(text, player)
    end

    # Хоткеи, активные во всех Runner-циклах игры: Ctrl+M — последний ход,
    # Ctrl+S — дистанция/статус. Модификатор обязателен — голые M/S не
    # должны ничего делать (в списке карт они бы ушли в быстрый поиск).
    def bind_game_hotkeys(runner)
      runner.on_key(KEY_LAST_MOVE) { say_last_move if main_modifier? }
      runner.on_key(KEY_STATUS) { say_status if main_modifier? }
    end

    # Главный модификатор Элтена (на Windows — Control) зажат.
    def main_modifier?
      modifier_held?(:main_modifier)
    end

    # Ctrl+M: последний ход
    def say_last_move
      if @move_history && @move_history.any?
        speak(@move_history.last)
      else
        speak(_('No moves yet.'))
      end
    end

    # Ctrl+S: дистанция и можно ли ехать (что мешает — если мешает)
    def say_status
      return speak(_('No game in progress.')) unless @human && @game

      car = @human.car
      blockers = move_blockers(car)
      text =
        if blockers.empty?
          _('%{d} miles. You can move.') % { d: car.distance }
        else
          _('%{d} miles. You cannot move: %{reasons}.') % { d: car.distance, reasons: blockers.join(', ') }
        end
      speak(text)
    end

    # Что мешает ехать — фразами ушной игры («Мотор заглушен», «Бензин слит»...).
    def move_blockers(car)
      blockers = []
      blockers << _('Fuel drained') if car.stalled_by?(:empty_tank)
      blockers << _('Tire flat') if car.stalled_by?(:flat_tire)
      blockers << _('In an accident') if car.stalled_by?(:accident)
      immobilized = IMMOBILIZING.any? { |t| car.stalled_by?(t) }
      blockers << _('Engine stalled') if car.stalled_by?(:stall) || (!car.running? && !immobilized)
      blockers << _('Speed limited') if car.speed_limited?
      blockers << _('Turned back') if car.reversed?
      blockers
    end

    # Обёртка для обработчиков Ctrl+M/Ctrl+S: ни одно исключение не должно
    # вылететь из обработчика клавиш внутрь Runner (защита от вылета Elten).
    def safely
      yield
    rescue StandardError
      begin
        speak(_('Cannot display the status.'))
      rescue StandardError
        nil
      end
    end

    def announce_result
      winner = @game.winner
      if winner.equal?(@human)
        @audio.win
        alert(_('You are at the finish line. Congratulations!'), true)
      elsif winner != nil
        @audio.lose
        alert(_('The bot is at the finish line.'), true)
      else
        alert(_('The deck ran out. Draw.'), true)
      end
    end

    def show_help
      display_text([
        _('The goal is to be the first to cover the target distance exactly, without overshooting.'),
        _('Distance cards (25/50/75/100/200 miles) move you forward once your car is started and nothing blocks it.'),
        _('Hazard cards are played against an opponent: stall the engine, empty the tank, flat tire, accident, U-turn, speed limit, skip a turn.'),
        _('Remedy cards fix your own car: start the engine, refuel, fix the tire, repair after accident, end of U-turn, end of speed limit.'),
        _('Safety cards are played on yourself once and permanently block one kind of hazard. Playing one for the first time keeps your turn.'),
        _("If a card can't take effect (for example, refueling a full tank), it is simply discarded and the turn passes on."),
        _('During the game: Ctrl+M — the last move, Ctrl+S — your distance and whether you can move. Escape — end the game.')
      ].join("\n\n"), header: _('Rules'))
    end
  end
end
