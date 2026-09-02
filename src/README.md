# MileByMile for Elten

A port of the game to the Elten 3.0 API (following the AudioMemory /
Purrposterous samples from pajper). Bot-only mode for now — multiplayer
is on hold at Dawid Pieper's request until the new signalling protocol
is ready.

## Structure

```
__app.rb                          — entry point + Elten3AppInfo manifest
__manifest.json                   — duplicate manifest (matches the samples' convention)
lib/mile_by_mile/                 — COPY of the game engine from ../lib/mile_by_mile
                                     (kept in sync via ../sync_engine.sh)
lib/mile_by_mile_elten/
  bot.rb                          — AI opponent
  audio.rb                        — play_app_sound wrapper, sound name contract
  ui.rb                           — menu, player/bot turns, help
Audio/                            — sound assets (flat, see naming note below)
locale/                           — ru/pl gettext catalogs (po + compiled mo)
```
Dev harnesses (bot-vs-bot fuzz, UI smoke) live in `../dev/`; the install
script is `../install_elten.sh`; the engine sync script is `../sync_engine.sh`.

## Important: don't edit the engine here

`lib/mile_by_mile/` inside `elten_app/` is a copy. Make changes in the
top-level `lib/mile_by_mile/`, then run `../sync_engine.sh` to copy them
here. Otherwise the two copies drift apart.

## Installing into Elten (dev)

The app is installed as an UNBUILT source folder — no `.eltenapp` packaging.
Elten 3 loads folder apps from `apps/src/` directly, but only in developer
mode (launch Elten with `/developer`, or use Выход → «Перезагрузить в режиме
разработчика»). Dawid bundles and signs the app for release; for daily
iteration this script is all we need:

```bash
sh install_elten.sh
```

It copies code, `Audio/` and `locale/` into
`<appdata>/elten/apps/src/MileByMile` (Windows Git Bash: `%APPDATA%`;
Linux: `$XDG_DATA_HOME`/`~/.local/share`). A `.mo` that is older than its
`.po` is rebuilt automatically when `ruby` is available. Restart Elten
(Выход → Перезагрузить) to pick the app up.

**Windows gotcha (CRLF):** Elten 3.0.1's `Elten3AppInfo` parser fails on
CRLF line endings — the closing `=end Elten3AppInfo` regex misses the
trailing `\r` and the program is flagged "incompatible" in the program
manager. Git for Windows checks out with CRLF by default. `.gitattributes`
forces LF for `.rb`/`.json`/`.po`, and `install_elten.sh` normalizes the
installed copy to LF as a safety net, so this is handled automatically.

## Bot AI

Turn priority: 1) repair/start/un-reverse your own car, 2) play a safety
card you don't have yet (keeps your turn), 3) play a hazard on the
leader if it would actually do something (target lacks the matching
immunity, condition applies), 4) the longest legal distance card,
5) any card in hand as a last resort (after the engine fix, any card
that can't take effect is simply discarded instead of crashing the game).

## Testing the bot for crashes

```bash
ruby dev/fuzz_bot_vs_bot.rb 1000
```

Runs 1000 bot-vs-bot games outside the Elten runtime (engine only, no
Program/UI widgets needed), checking that the bot's decisions never
raise an exception inside the game.

```bash
ruby dev/harness_ui_smoke.rb 100
```

Runs 100 full games through the actual `MileByMileElten::UI` class
(menu, human turn, bot turn, help) using minimal stand-ins for the
Elten API (`_`, `selector`, `alert`, `EditBox`, `Program`), so the UI
integration itself is covered, not just the engine.

## Localization (po/mo)

Source language in the code is English (`_('...')` msgid). `locale/ru.po`
and `locale/pl.po` are the Russian and Polish translations, compiled to
`locale/ru.mo` / `locale/pl.mo` via `msgfmt`. Card names are translated
via `_(card.name)` in the UI layer — the engine itself
(`lib/mile_by_mile`) has no gettext dependency, so it stays
self-contained and testable outside Elten.

`install_elten.sh` rebuilds a stale `.mo` from its `.po` automatically
(no `msgfmt` here — a minimal .po→.mo compiler lives at `tools/po2mo.rb`).
To rebuild by hand:

```bash
ruby tools/po2mo.rb elten_app/locale/ru.po elten_app/locale/ru.mo
ruby tools/po2mo.rb elten_app/locale/pl.po elten_app/locale/pl.mo
```

## Sound — an important finding

In `elten3/src/eapi/program.rb`, sound assets are looked up by basename
only, extension stripped (`add_sound_asset` always does
`File.basename(path, ext)`), and the physical loader
(`collect_physical_sound_assets`) scans the `Audio/` folder WITHOUT
recursing into subfolders (`Dir.children`, not `Dir.glob("**/*")`). So
all the files you sent (`cars/fail/tire.ogg`, `horses/success/tire.ogg`,
etc.) got flattened into `elten_app/Audio/` with unique names like
`cars_fail_tire.ogg`, `horses_success_tire.ogg`, `prot_tire.ogg`, to
avoid a basename collision (`tire` existed in 5 different subfolders).
If your packaging tool works differently (e.g. keeps the relative path
as the name), let me know and I'll rewire the names in `audio.rb`.

Naming scheme: `<variant>_<0|25|50|75|100|200>`, `<variant>_bibip`,
`<variant>_welcome`, `<variant>_fail_<key>`, `<variant>_success_<key>`,
`prot_<key>`, `wow`. `variant` = `cars`/`horses`. `key` = `ready` (engine),
`tank` (fuel), `tire` (wheel), `wheel` (u-turn), `seat` (accident),
`speed` (speed limit), `pass` (skip turn).

## What's new in this round

- Card theme (cars/horses) and distance selection at the start of a game.
- Action phrases now match the original ear.social game (screen reader
  and speech): target-centered wording for hazards/protections, horses
  use their own verbs (saddle up / feed / shoe / rest).
- Sounds verified against the original Pascal: only real state changes
  make a sound (a card wasted into the discard is silent); the speed
  limit and protections are quieter; `wow` plays when you overtake the
  opponent, not on the finish line; the skip-turn card sounds like a
  success card; the game starts with the welcome fanfare (softer for
  horses) and a horn 3 seconds later.
- Drawing a card is voiced; right before the human's turn the screen
  reader speaks one combined line: what the bot did + what you just
  drew + "Your turn" — e.g. `Bot moved 50 miles. You drew 100 miles.
  Your turn.` (translated into ru/pl).

## What's new in this round

- Rules screen now uses Elten's `display_text` (a ReadOnly MultiLine
  EditBox dialog) instead of a hand-rolled `show_text` that did not exist
  in the Elten 3 API — opening Rules used to raise NoMethodError on a real
  runtime. The harness now exercises that path (regression check).
- Sound assets moved from `audio/` to `Audio/`:
  `collect_physical_sound_assets` scans the `Audio` folder at runtime and
  matches on the capital name, so the lowercase folder meant zero sounds
  on case-sensitive platforms (both as a source folder and once packaged).

## Next

- Real multiplayer — done on `EltenAPI::Communication` (Elten 3.0.2 RC 1):
  `create_session` + `session.invite` (host), `on_invitation` + `accept`
  (guest), `send_reliable` for moves, `close`/`leave` for exit. Settings
  travel in `session_metadata`; deck seed in the `start` packet keeps both
  engines identical.
- Online leaderboard via `server_table` (like AudioMemory) — not wired
  up yet.
