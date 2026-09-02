# frozen_string_literal: true

# Two-sided multiplayer smoke test. Simulates host and guest as two UI
# instances connected through an in-memory transport, each driven by its own
# thread. Both humans always play the first card in their hand (ListBox stub).
# Verifies: handshake order, that both engines finish in sync, and that the
# winners agree.

require 'json'
require_relative '../lib/mile_by_mile'
require_relative '../src/lib/mile_by_mile_elten/bot'
require_relative '../src/lib/mile_by_mile_elten/audio'
require_relative '../src/lib/mile_by_mile_elten/ui'

def parse_type?(data)
  JSON.parse(data.to_s.dup.force_encoding(Encoding::UTF_8))['type']
rescue JSON::ParserError, TypeError
  nil
end

def parse_move?(data)
  parse_type?(data) == 'move'
end

# --- minimal Elten API stubs ---
def _(s) = s.to_s
def n_(a, b, n) = n == 1 ? a : b

ALERTS = []
def alert(text, _wait = true)
  ALERTS << text
end

$selector_script = []
def selector(options, header: '', start_index: 0, cancel_index: nil, **_kw)
  idx = $selector_script.empty? ? 0 : $selector_script.shift
  idx = [options.size - 1, idx].min
  idx
end

$confirm_result = true
def confirm(_text = '')
  $confirm_result
end

def dialog_open; end
def dialog_close; end

SPEECH = []
def speak(text, stop: true, **_kw)
  SPEECH << text
end

$input_text_result = 'Guest'
def input_text(_header, **_kw)
  $input_text_result
end

module EltenLink
  def self.client(ctx)
    ctx
  end

  module Profiles
    def self.card(_client, user)
      UserCard.new(name: user, status: Status.new(online: true))
    end
  end
end

class Status
  attr_reader :online

  def initialize(online:)
    @online = online
  end
end

class UserCard
  attr_reader :name, :status

  def initialize(name:, status:)
    @name = name
    @status = status
  end
end

$form_values_script = []
class ChoiceListBox
  attr_reader :rows

  def initialize(rows, header: '', index: 0, quiet: false, flags: 0, **_kw)
    @rows = rows
  end

  def value(row)
    @rows[row][2]
  end

  def update; end
end

class Button
  def initialize(label)
    @label = label
    @events = Hash.new { |h, k| h[k] = [] }
  end

  def on(event, &block)
    @events[event] << block
    self
  end

  def press
    @events[:press].each(&:call)
  end

  def update; end
end

class Form
  attr_accessor :accept_button, :cancel_button

  def initialize(fields, index: 0)
    @fields = fields
  end

  def wait
    vals = $form_values_script.empty? ? [0, 0, 0] : $form_values_script.shift
    @fields.each_with_index do |field, i|
      field.rows[0][2] = vals[i] if field.is_a?(ChoiceListBox) && vals[i]
    end
    accept_button.press if accept_button
  end

  def resume; end

  def update; end
end

DISPLAYED_TEXT = []
def display_text(text, header: '', **_kw)
  DISPLAYED_TEXT << [header, text]
end

# ListBox stub for the unified game screen: the SAME list instance lives for
# the whole game, so "the human plays the focused card on each of their turns"
# is simulated by re-firing :select whenever the list is refreshed (options=)
# while that side's phase is :human. Ownership is thread-local — the host and
# guest UIs run in separate threads with their own lists.
class ListBox
  module Flags
    MultiSelection = 1
    AnyDir = 16
    HotKeys = 32
  end

  attr_accessor :index
  attr_reader :options

  def initialize(options, header: '', index: 0, flags: 0, quiet: false, **_kw)
    @options = options
    @index = index
    @owner = Thread.current[:miley_ui]
    @events = Hash.new { |h, k| h[k] = [] }
    @armed = false
  end

  def on(event, &block)
    @events[event] << block
    self
  end

  def focus(*_args); end

  def set_item_status(*_args); end

  def human_phase?
    ui = @owner
    ui && ui.instance_variable_get(:@phase) == :human
  end

  def options=(opts)
    @options = opts
    @armed = human_phase? && !opts.empty?
  end

  def update
    return unless human_phase?
    return if @owner.instance_variable_get(:@pending_pick)
    return unless @armed && !@options.empty?

    @armed = false
    @events[:select].each { |block| block.call([@index]) }
  end
end

# Endless Runner (until stop) with wall-clock one-shot/every timers — the real
# Elten Runner blocks until stopped, which is what multiplayer waits need.
class Runner
  attr_reader :result

  def initialize(frame_interval: 0.0)
    @timers = []
    @key_handlers = []
    @tick = nil
    @running = false
    @result = nil
  end

  def after(delay, phase: :timer, &block)
    @timers << { phase: :after, block: block, fired: false, delay: delay }
    self
  end

  def every(_interval, **_, &block)
    @timers << { phase: :every, block: block, fired: false, delay: 0 }
    self
  end

  def on_key(_key, **_kw, &block)
    @key_handlers << block
    self
  end

  def on_tick(&block)
    @tick = block
    self
  end

  def run
    @running = true
    @result = nil
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @timers.each { |t| t[:fire_at] = start + t[:delay].to_f }
    while @running
      @tick.call(self) if @tick
      break unless @running

      @timers.each do |t|
        next if t[:fired]
        next unless Process.clock_gettime(Process::CLOCK_MONOTONIC) >= t[:fire_at]

        t[:fired] = true
        t[:block].call(self)
      end
      sleep 0.001
    end
    @result
  end

  def stop(result = nil)
    @result = result
    @running = false
    result
  end
end

class EditBox
  module Flags
    MultiLine = 1
    ReadOnly = 2
  end

  def initialize(header, type:, text:, quiet:); end
  def update; end
end

# --- in-memory EltenAPI::Communication transport ---
# Two fake endpoints (host/guest) exchange invitations and reliable messages
# through a shared registry. Each side gets its own Session handle; sending
# routes the payload to the peer's handle, which emits on its callbacks (and
# buffers until a callback is registered — mirrors the server-side queue).

class FakeParticipant
  attr_reader :user

  def initialize(user)
    @user = user
  end
end

class FakeMessage
  attr_reader :data

  def initialize(data)
    @data = data
  end
end

class FakeOutgoingInvitation
  attr_reader :status

  def initialize
    @status = :pending
  end

  def accepted!
    @status = :accepted
  end

  def rejected!
    @status = :rejected
  end

  def cancelled!
    @status = :cancelled
  end
end

class FakeSession
  attr_reader :id, :metadata, :my_nick, :sent, :received

  def initialize(id, metadata:, my_nick:, transport:)
    @id = id
    @metadata = metadata
    @my_nick = my_nick
    @transport = transport
    @callbacks = Hash.new { |h, k| h[k] = [] }
    @pending = []
    @sent = []
    @received = []
  end

  def on_reliable(&block)
    @callbacks[:reliable] << block
    flush_pending(:reliable)
    self
  end

  def on_participant_joined(&block)
    @callbacks[:participant_joined] << block
    flush_pending(:participant_joined)
    self
  end

  def on_participant_left(&block)
    @callbacks[:participant_left] << block
    self
  end

  def on_closed(&block)
    @callbacks[:closed] << block
    self
  end

  def deliver_participant_joined(participant)
    if @callbacks[:participant_joined].any?
      @callbacks[:participant_joined].each { |b| b.call(participant) }
    else
      @pending << [:participant_joined, participant]
    end
  end

  def participants
    @transport.session_participants(self)
  end

  def invite(user)
    @transport.invite(@my_nick, user, self)
  end

  def send_reliable(data)
    @sent << data
    @transport.send_reliable(self, data)
    self
  end

  def close
    @transport.close_session(self)
  end

  def leave
    @transport.leave_session(self)
  end

  def deliver_reliable(data)
    @received << data
    if @callbacks[:reliable].any?
      @callbacks[:reliable].each { |b| b.call(FakeMessage.new(data)) }
    else
      @pending << [:reliable, data]
    end
  end

  def deliver_closed(reason)
    @callbacks[:closed].each { |b| b.call(reason) }
  end

  def deliver_participant_left(participant, reason)
    @callbacks[:participant_left].each { |b| b.call(participant, reason) }
  end

  private

  def flush_pending(kind)
    @pending.delete_if do |k, data|
      next false unless k == kind

      @callbacks[kind].each { |b| b.call(FakeMessage.new(data)) }
      true
    end
  end
end

class FakeInvitation
  attr_reader :sender, :session_metadata, :status, :guest_nick

  def initialize(host_nick, guest_session, endpoint)
    @sender = FakeParticipant.new(host_nick)
    @session_metadata = guest_session.metadata
    @endpoint = endpoint
    @guest_nick = guest_session.my_nick
    @status = :pending
  end

  def accept(metadata: {})
    @status = :accepted
    @endpoint.accept_invitation(self)
  end

  def reject
    @status = :rejected
    @endpoint.reject_invitation(self)
    true
  end
end

class FakeEndpoint
  attr_reader :session

  def initialize(nick, transport)
    @nick = nick
    @transport = transport
    @invitation_callbacks = []
    @pending_invitations = []
    @session = nil
  end

  def on_invitation(&block)
    @invitation_callbacks << block
    pending = @pending_invitations
    @pending_invitations = []
    pending.each { |inv| block.call(inv) }
    self
  end

  def create_session(metadata: {}, capacity: 2, **_kw)
    @session = @transport.create_session(@nick, metadata)
  end

  def accept_invitation(invitation)
    @session = @transport.accept(invitation)
  end

  def reject_invitation(invitation)
    @transport.reject(invitation)
  end

  def deliver_invitation(invitation)
    if @invitation_callbacks.any?
      @invitation_callbacks.each { |b| b.call(invitation) }
    else
      @pending_invitations << invitation
    end
  end
end

class FakeProgram
  attr_reader :nick, :communication

  def initialize(nick, transport)
    @nick = nick
    @communication = FakeEndpoint.new(nick, transport)
  end

  def play_app_sound(name, **_kw)
    true
  end
end

# Routes invitations/messages between two fake endpoints; keeps one session
# record per game with separate host/guest handles.
class Transport
  def initialize
    @peers = {}
    @sessions = {}
    @invitations = {}
    @mutex = Mutex.new
  end

  def register(nick, endpoint)
    @peers[nick] = endpoint
  end

  def create_session(host_nick, metadata)
    @mutex.synchronize do
      id = "s#{@sessions.size + 1}"
      session = FakeSession.new(id, metadata: metadata, my_nick: host_nick, transport: self)
      @sessions[id] = { host: session, guest: nil, members: [host_nick] }
      session
    end
  end

  def guest_session(host_session)
    @mutex.synchronize { @sessions[host_session.id][:guest] }
  end

  def invite(host_nick, guest_nick, session)
    @mutex.synchronize do
      rec = @sessions[session.id]
      guest_session = FakeSession.new(session.id, metadata: session.metadata,
                                                   my_nick: guest_nick, transport: self)
      rec[:guest] = guest_session
      outgoing = FakeOutgoingInvitation.new
      @invitations[[host_nick, guest_nick]] = outgoing
      invitation = FakeInvitation.new(host_nick, guest_session, @peers[guest_nick])
      @peers[guest_nick].deliver_invitation(invitation)
      outgoing
    end
  end

  def accept(invitation)
    @mutex.synchronize do
      outgoing = @invitations[[invitation.sender.user, invitation.guest_nick]]
      outgoing&.accepted!
      rec = @sessions.values.find { |r| r[:guest]&.my_nick == invitation.guest_nick }
      rec[:members] << invitation.guest_nick unless rec[:members].include?(invitation.guest_nick)
      rec[:guest]
    end
  end

  def reject(invitation)
    @mutex.synchronize { @invitations[[invitation.sender.user, invitation.guest_nick]]&.rejected! }
  end

  def session_participants(session)
    @mutex.synchronize do
      rec = @sessions[session.id]
      rec[:members].map { |nick| FakeParticipant.new(nick) }
    end
  end

  def send_reliable(session, data)
    @mutex.synchronize do
      rec = @sessions[session.id]
      peer = session.my_nick == rec[:host].my_nick ? rec[:guest] : rec[:host]
      peer.deliver_reliable(data)
    end
  end

  def close_session(session)
    @mutex.synchronize do
      rec = @sessions[session.id]
      rec[:host].deliver_closed(:closed)
      rec[:guest]&.deliver_closed(:closed)
    end
  end

  def leave_session(session)
    @mutex.synchronize do
      rec = @sessions[session.id]
      peer = session.my_nick == rec[:host].my_nick ? rec[:guest] : rec[:host]
      session.deliver_closed(:left)
      peer&.deliver_participant_left(FakeParticipant.new(session.my_nick), :left)
    end
  end
end

# --- run the two-sided game through the unified game screen ---

# Wire a host/guest UI pair over the in-memory transport: host creates the
# session and both sides register their session listeners up front (the same
# contract start_hosted_game / join_and_wait_start expect on the real client).
def link_game
  transport = Transport.new
  host_prog = FakeProgram.new('Host', transport)
  guest_prog = FakeProgram.new('Guest', transport)
  host_ui = MileByMileElten::UI.new(host_prog)
  guest_ui = MileByMileElten::UI.new(guest_prog)
  transport.register('Host', host_prog.communication)
  transport.register('Guest', guest_prog.communication)

  host_session = host_prog.communication.create_session(metadata: {})
  transport.invite('Host', 'Guest', host_session)
  guest_session = transport.guest_session(host_session)

  host_ui.instance_variable_set(:@session, host_session)
  host_ui.instance_variable_set(:@mp_host, true)
  host_ui.send(:register_session_listeners, host_session)
  guest_ui.instance_variable_set(:@session, guest_session)
  guest_ui.instance_variable_set(:@mp_host, false)
  guest_ui.send(:register_session_listeners, guest_session)

  [transport, host_prog, guest_prog, host_ui, guest_ui, host_session, guest_session]
end

# Start host + guest threads. The unified ListBox stub needs its owning UI in a
# thread-local, since both sides run concurrently in their own threads.
def spawn_pair(host_ui, guest_ui, distance, seconds: 60)
  result = {}
  host_thread = Thread.new do
    Thread.current[:miley_ui] = host_ui
    result[:host] = host_ui.send(:start_hosted_game, :cars, distance, :shared, 3, 'Guest')
  end
  guest_thread = Thread.new do
    Thread.current[:miley_ui] = guest_ui
    result[:guest] = guest_ui.send(:join_and_wait_start, 'Host', :cars, distance, :shared, 3)
  end
  watchdog = Thread.new do
    sleep seconds
    host_thread.kill
    guest_thread.kill
    abort "MP SMOKE HUNG (desync, distance=#{distance})"
  end
  [result, host_thread, guest_thread, watchdog]
end

errors = 0

# Scenario 1: N full two-sided games to a natural finish, engines in sync.
GAMES = (ARGV[0] || 5).to_i
GAMES.times do |i|
  Thread.abort_on_exception = true
  ALERTS.clear
  SPEECH.clear
  _transport, _hp, _gp, host_ui, guest_ui, host_session, guest_session = link_game
  result, host_thread, guest_thread, watchdog = spawn_pair(host_ui, guest_ui, 1000, seconds: 30)
  host_thread.join
  guest_thread.join
  watchdog.kill

  hg = host_ui.instance_variable_get(:@game)
  gg = guest_ui.instance_variable_get(:@game)
  host_moves = host_session.sent.count { |d| parse_move?(d) }
  guest_moves = guest_session.sent.count { |d| parse_move?(d) }
  host_start = host_session.sent.any? { |d| parse_type?(d) == 'start' }
  guest_got_start = guest_session.received.any? { |d| parse_type?(d) == 'start' }

  ok = true
  ok = false unless result[:host] == :played
  ok = false unless result[:guest] == :played
  ok = false unless hg.finished? && gg.finished?
  ok = false unless host_moves + guest_moves > 0
  ok = false unless host_start
  ok = false unless guest_got_start
  # имена игроков на двух сторонах разные (каждый называет себя "You"),
  # поэтому сверяем ПОЗИЦИЮ победителя в массиве игроков — движки идентичны
  widx_h = hg.players.index(hg.winner)
  widx_g = gg.players.index(gg.winner)
  ok = false unless widx_h == widx_g

  puts "MP GAME ##{i}: host=#{result[:host].inspect} guest=#{result[:guest].inspect} " \
       "finished(h=#{hg.finished?},g=#{gg.finished?}) " \
       "moves(h=#{host_moves},g=#{guest_moves}) " \
       "start(sent=#{host_start},got=#{guest_got_start}) " \
       "winner_slot(h=#{widx_h.inspect},g=#{widx_g.inspect}) sync=#{ok ? 'yes' : 'NO'}"

  errors += 1 unless ok
end

# Scenario 2: in-game chat (Ctrl+/ both ways) then the opponent quits mid-game.
Thread.abort_on_exception = true
ALERTS.clear
SPEECH.clear
transport, _hp, _gp, host_ui, guest_ui, _host_session, guest_session = link_game
result, host_thread, guest_thread, watchdog = spawn_pair(host_ui, guest_ui, 1_000_000, seconds: 20)
sleep 0.3 # let both sides reach the unified screen and open a session

$input_text_result = 'hello from host'
host_ui.send(:compose_chat_message)
deadline = Time.now + 4
until guest_ui.instance_variable_get(:@chat_history).any? { |_n, t| t == 'hello from host' } || Time.now > deadline
  sleep 0.02
end
guest_got_msg = guest_ui.instance_variable_get(:@chat_history).any? { |n, t| n == 'Host' && t == 'hello from host' }
host_echo = host_ui.instance_variable_get(:@chat_history).any? { |n, t| n == 'You' && t == 'hello from host' }

$input_text_result = 'hi from guest'
guest_ui.send(:compose_chat_message)
deadline = Time.now + 4
until host_ui.instance_variable_get(:@chat_history).any? { |_n, t| t == 'hi from guest' } || Time.now > deadline
  sleep 0.02
end
host_got_reply = host_ui.instance_variable_get(:@chat_history).any? { |n, t| n == 'Guest' && t == 'hi from guest' }
guest_echo = guest_ui.instance_variable_get(:@chat_history).any? { |n, t| n == 'You' && t == 'hi from guest' }
heard = SPEECH.any? { |s| s.include?('hello from host') } && SPEECH.any? { |s| s.include?('hi from guest') }

# соперник (гость) уходит посреди партии — хост должен увидеть сдачу, а не
# «The game is over»: в ALERTS обязана появиться фраза c 'conceded'
transport.leave_session(guest_session)
host_thread.join
guest_thread.join
watchdog.kill

hg = host_ui.instance_variable_get(:@game)
conceded = ALERTS.any? { |a| a.include?('conceded') }
host_not_finished = !hg.finished?

chat_ok = guest_got_msg && host_echo && host_got_reply && guest_echo && heard
puts "CHAT: host->guest=#{guest_got_msg} echo(host)=#{host_echo} guest->host=#{host_got_reply} echo(guest)=#{guest_echo} speech=#{heard} all=#{chat_ok ? 'yes' : 'NO'}"
puts "CONCEDE on host: message=#{conceded} game_not_finished=#{host_not_finished} ok=#{conceded && host_not_finished ? 'yes' : 'NO'}"
errors += 1 unless chat_ok
errors += 1 unless conceded && host_not_finished

puts errors.zero? ? 'ALL MP GAMES IN SYNC' : "MP FAILURES: #{errors}"
exit(errors.zero? ? 0 : 1)
