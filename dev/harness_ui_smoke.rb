# frozen_string_literal: true

require_relative '../lib/mile_by_mile'
require_relative '../elten_app/lib/mile_by_mile_elten/bot'
require_relative '../elten_app/lib/mile_by_mile_elten/audio'
require_relative '../elten_app/lib/mile_by_mile_elten/ui'

# --- minimal Elten API stubs so the UI can run outside Elten ---
def _(s) = s.to_s
def n_(a, b, n) = n == 1 ? a : b

ALERTS = []
def alert(text, _wait = true)
  ALERTS << text
end

# selector: if $selector_script (array of indices) is set, consume it in order,
# otherwise always pick the first available option (index 0)
$selector_script = []
def selector(options, header: '', start_index: 0, cancel_index: nil, **_kw)
  idx = $selector_script.empty? ? 0 : $selector_script.shift
  idx = [options.size - 1, idx].min
  idx
end

def confirm(_text = '')
  false
end

def dialog_open; end
def dialog_close; end

SPEECH = []
def speak(text, stop: true, **_kw)
  SPEECH << text
end

# Form settings stub: $form_values_script holds [variant, distance, deck] triples,
# one per game, consumed in order by Form#wait. Default: [0, 0, 0].
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

# ListBox stub: Enter on the first card is simulated on the first update call,
# so the human always plays the first card in hand.
class ListBox
  module Flags
    MultiSelection = 1
    AnyDir = 16
    HotKeys = 32
  end

  attr_reader :index, :options

  def initialize(options, header: '', index: 0, flags: 0, quiet: false, **_kw)
    @options = options
    @index = index
    @events = Hash.new { |h, k| h[k] = [] }
    @updated = false
  end

  def on(event, &block)
    @events[event] << block
    self
  end

  def focus(*_args); end

  def set_item_status(*_args); end

  def update
    return if @updated || @options.empty?

    @updated = true
    @index = 0
    @events[:select].each { |block| block.call([@index]) }
  end
end

# Runner stub: run ticks (driving on_tick) then fire one-shot timers, stopping
# when the runner is stopped from inside a handler.
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
    @timers << { phase: :after, block: block, fired: false }
    self
  end

  def every(_interval, **_, &block)
    @timers << { phase: :every, block: block, fired: false }
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
    200.times do
      break unless @running

      @tick.call(self) if @tick
      break unless @running

      @timers.each do |t|
        next if t[:fired]
        next unless t[:phase] == :after

        t[:fired] = true
        t[:block].call(self)
      end
      break unless @running
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

class FakeProgram
  def play_app_sound(name, **_kw)
    true
  end

  def read_json(_path, default: nil, **_kw)
    default
  end

  def write_json(_path, *_args, **_kw)
    true
  end
end

# --- run N full games through MileByMileElten::UI ---
GAMES = (ARGV[0] || 30).to_i
crashes = 0

GAMES.times do |i|
  ALERTS.clear
  SPEECH.clear
  program = FakeProgram.new
  ui = MileByMileElten::UI.new(program)
  # scenario: variant (0=cars/1=horses alternating), distance (0=1000),
  # deck (0=each own deck, 3=3 common decks alternating), then the human
  # always plays the first card in hand until the game ends.
  $form_values_script = [[i.even? ? 0 : 1, 0, i.even? ? 0 : 3]]

  begin
    ui.send(:play_vs_bot)
  rescue StandardError => e
    crashes += 1
    puts "GAME ##{i} CRASHED: #{e.class}: #{e.message}"
    puts e.backtrace.first(6)
  end
end

# the F2/F4 handlers must produce speech without crashing
ui = MileByMileElten::UI.new(FakeProgram.new)
ui.instance_variable_set(:@human, MileByMile::Player.new('You'))
ui.instance_variable_set(:@move_history, ['Bot moved 50 miles.'])
status_crashes = 0
begin
  SPEECH.clear
  ui.send(:say_last_move)
  ui.send(:say_status)
  status_crashes = SPEECH.grep(/moved 50 miles/).empty? ? 1 : 0
rescue StandardError => e
  status_crashes += 1
  puts "F2/F4 CRASHED: #{e.class}: #{e.message}"
end

# the Rules screen must render via Elten's display_text
help_crashes = 0
begin
  DISPLAYED_TEXT.clear
  ui = MileByMileElten::UI.new(FakeProgram.new)
  ui.send(:show_help)
  help_crashes = DISPLAYED_TEXT.empty? ? 1 : 0
rescue StandardError => e
  help_crashes += 1
  puts "HELP CRASHED: #{e.class}: #{e.message}"
end

puts "Done: #{GAMES} games via the UI (human always plays the first card in hand), crashes: #{crashes}"
puts "Ctrl+M/S status speech: #{status_crashes.zero? ? 'yes' : 'NO'}"
puts "Rules screen rendered via display_text: #{help_crashes.zero? ? 'yes' : 'NO'}"
exit(crashes.zero? && status_crashes.zero? && help_crashes.zero? ? 0 : 1)
