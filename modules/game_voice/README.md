# game_voice (Mythos Voz)

Voice chat in the game panel: the party room, the guild and officers rooms,
public rooms and event stages, Discord-like. Audio goes through the
`mythos-voz` relay (Go, `tools/voz` in the server repository); canary only
grants the rights, over extended opcode 142.

This module is phase 3 of the voice plan: the whole panel and protocol with
the **mock** and **lite** engines. The **full** engine (real audio) needs the
`g_voice` C++ binding of phases 4 and 6; until then `EngineFull.available()`
is false.

## Files

| File | What it holds |
|---|---|
| `voice_state.lua` | The pure part: state machine, opcode 142 and relay messages, rooms and members, control rate limit, preferences, report builder. No `g_*` call and no widget: it runs in plain LuaJIT. |
| `engine_full.lua` | Thin wrapper over `g_voice` (only if the binding exists and `isSupported()`). |
| `engine_lite.lua` | Control messages only, over `HTTP.webSocket`: presence, rooms, moves, moderation. No audio. |
| `engine_mock.lua` | A relay inside the client (welcome, a roster of 4 made-up players, speaking edges every 1-3 s), plus canary's opcode 142 answers. |
| `voice.lua` | The glue: opcode 142, engine choice, push-to-talk keys, ducking, game start/end. |
| `voice_ui.lua`, `voice.otui` | The panel, member rows, right-click menus, volume popup, report window, over-head icon. |
| `voice_settings.lua`, `voicesettings.otui`, `voiceonboard.otui` | Settings window and the one-time onboarding. |
| `voice_locale.lua` | Portuguese for every English string (Latin-1 as `\ddd` escapes), merged into the `pt` locale on first use, only for keys `pt.lua` lacks. |
| `images/` | Icons (generated pixel art; 16x16 header buttons, 12x12 member icons, the 40x20 top-menu toggle). |

Tests: `luajit tools/voz-luatest/game_voice_test.lua` from the client repo root.

## Cost when the server has no voice

The module loads with `game_interface` (load-later, after `game_partyminimap`).
At login it sends one `{"a":"hi"}` on opcode 142 and registers the opcode
handler. That is all: no keybind, no widget, no locale table, no engine and no
timer exist until canary answers `cfg` with `on=true` (or tells of a ban).
A server without the voice scripts never answers, so nothing else happens.
Junk on opcode 142 changes nothing: malformed JSON, a `tok` before `cfg`, a
`rep` when no report is pending, numbers that are text, NaN or infinite. If
the module failed to load (a file missing), `load-later` logs one error and
the game is unaffected. An error inside the panel code is logged
(`game_voice: <event>: ...`) and never leaves the state machine half way:
voice.lua calls the UI under `pcall`. The stub-client test at the end of
`game_voice_test.lua` checks all of this on `voice.lua` itself.

## Engines

Chosen at each game start:

1. `full` if `g_voice` exists and `g_voice.isSupported()`;
2. else `lite` if `HTTP.webSocket` and `g_http.ws` exist (today's Windows and browser builds);
3. `mock` only when `g_settings.getValue('voice-mock') == 'true'` (developers:
   `g_settings.setValue('voice-mock', 'true')` in the terminal, then log in again).
   In mock mode opcode 142 never reaches the server: `EngineMock.reply` answers.

The engine is created on the first connect, never before. All engines report
through one sink with the shape of `g_voice.onVoiceEvent(type, s, a, b)`:

| type | fields |
|---|---|
| `state` | `s` = `connecting`, `open`, `closed`, `error`; `a` = close code (or nil) |
| `ctl` | `s` = one relay control message (JSON text) |
| `spk` | `a` = sid, `b` = 1/0 (speaking edges) |
| `talk` | `a` = slot or -1 (the local gate) |
| `level` | `a` = dBFS, only while the settings window is open (`setMeter`) |
| `mic` | `s` = `ok`, `denied`, `nodevice` |
| `devices` | the device lists changed |

Contract for the phase 4/6 `g_voice` binding, used by `engine_full.lua`:
`connect(url, token, clientTag, build)` sends the hello itself once open;
`disconnect()`, `sendControl(json)`, `setTransmit(slot|-1)`, `setMode(vad)`,
`setVadThreshold(db)`, `setPreset(0 normal|1 eco|2 high)`,
`setInputDevice(name)`, `setOutputDevice(name)`, `getInputDevices()` and
`getOutputDevices()` (arrays of names), `setInputGain(x)`,
`setOutputVolume(x)`, `setUserVolume(sid, x)`, `setSlotVolume(slot, x)`,
`setDeafened(b)`, `setSelfMuted(b)`, `setMeter(b)`, `setPttMouse(btn, slot)`
(browser; btn 3 or 4, slot -1 to turn off), `setGlobalPtt(vk)` (Windows; a
virtual-key code, 0 to turn off), `startLocalTest(b)`. The wrapper drops a
`closed`/`error` state that arrives after its own `disconnect()`.

## State machine (`voice_state.lua`)

```
OFF --game start--> WAIT_CFG --cfg off--> DISABLED (beta/off/bad url, invisible)
                       |                  BLOCKED banned (the panel shows the date; no onboarding)
                       +--cfg on--> READY --"Turn voice on"--> WAIT_TOKEN
                       +--cfg on and this character opted in -> WAIT_TOKEN
WAIT_TOKEN --tok--> CONNECTING --welcome--> ONLINE
CONNECTING/ONLINE --close--> see below
BACKOFF --timer--> CONNECTING (fresh unused token) or WAIT_TOKEN (asks one)
any --game end--> OFF
```

| Close | Action |
|---|---|
| 4401 | ask `{a:'tok'}` once, at once; a second 4401 before 30 s online backs off |
| 4403 | BLOCKED banned |
| 4409 | BLOCKED replaced ("Reconectar" button, no automatic retry; a later `cfg on` does not lift it either, or two windows would replace each other forever) |
| 4503 | BLOCKED off |
| 1012 | BACKOFF 1-5 s random, not counted as a failure |
| 4429, 4408, 1000, network, unknown | BACKOFF 1, 2, 4, 8, 16, 30, 60 s ±30%; the 10th failure in a row is FAILED (manual "Tentar de novo" only) |

The failure count (and the one-time 4401 retry) resets after 30 s online.
No token within 10 s, or no welcome within 15 s of connecting, counts as a
failure. Backoff and every other wait use `scheduleEvent`; nothing per frame.

## Protocol details and choices

Where the plan left room, the simplest safe option was taken:

- **Opcode 142 is registered raw** (`ProtocolGame.registerExtendedOpcode`) and
  decoded here with `pcall(json.decode)` and a 2048-byte cap
  (`VoiceState.decode`), instead of `registerExtendedJSONOpcode`, which raises
  a Lua error on malformed JSON. Messages go out as plain JSON with
  `sendExtendedOpcode`, as canary expects. A message over 2048 bytes is never
  sent. Canary must send each message as one plain JSON object (no `S`/`P`/`E`
  chunk prefix of `sendExtendedJSONOpcode`), at most 2048 bytes.
- **Relay control messages** are read up to 40 KB: a roster entry is at most
  66 bytes, so the 500-member cap fits; a bigger message is dropped whole.
- **Numbers from canary and the relay** (`psl`, `until`, `s`, `n`, the
  directory counts) go through `VoiceState.num`: text, NaN (`"nan"` reads as
  a number), infinities and tables become a clamped whole number or the
  default, so nothing odd reaches a timer, `string.format` or `os.date`.
- **Lite engine and close codes**: `HTTP.webSocket` reports every close as
  `close_code::normal` or `close_code::error ...`, without the number, so in
  lite every close is a network failure (backoff with a new token). Bans and
  the kill switch still reach lite clients through opcode 142 (`cfg on=false`,
  `err banned`). `engine_lite` parses a number from `close_code::<n>` if a
  later build adds it. It also drops its entry from `HTTP.operations` (which
  corelib never cleans for websockets).
- **Tokens**: a token is used once (hello or auth). A kept token is reused for
  a reconnect only if unused and younger than 100 s (TTL 120 s, 20 s margin;
  the client clock is not compared with the server's). Token requests keep
  canary's limits on the client side: 1 per 3 s and 30 per 10 minutes; `want`
  counts as a request. `err rate` delays the next request by `s`.
- Canary pushes a token every 240 s; the panel is drawn again only when the
  rooms the token lists changed.
- A token that arrives while connecting is sent as `auth` right after welcome.
  A token while online is sent as `auth`, then the party (and, with autoGuild,
  the guild) room is joined if the slot is empty; a room already in the slot
  is moved by the relay itself (`moved`).
- **Rejoin after a reconnect**: the party room comes from the token (autoParty),
  the guild/officers room is joined again only if the token still lists it,
  and the public room or event of before is joined again (the relay refuses it
  with `err room_denied` if the rights changed, which clears it).
- A party or guild room left by hand is not auto-joined again until its id
  changes (a new party epoch).
- **Control rate limit**: the relay allows 5/s, burst 10; this client sends at
  most 4/s after a burst of 8, through a queue of 256 (one `mute` for each
  muted player of a big guild roster; the relay keeps up to 256). A newer
  `mute` for the same player, `self`, `deaf`, `dir` or `auth` replaces the
  pending one. A saved mute or volume is sent once per player and relay
  session, even when the player is in two of our rooms.
- **Joins**: at most 10 a minute per relay session, the relay's own limit
  (over it the relay answers `rate` and, after 20 of those, closes 4429). A
  click over the budget does nothing and says "too fast; wait a moment".
  `dir` is asked at most every 2 s, and every 15 s only while the room list is
  unfolded and the panel open.
- **Leave** removes the room locally at once (the protocol defines no answer).
- **Deafen** also stops talking (as on Discord); self-mute and deafen are saved
  and sent again after each reconnect.
- **Moderation entries** show when this player's own row in that room has the
  moderator (32) or staff (16) flag; in the party room only the mute entries
  show unless staff. The relay checks every action again.
- **Reports**: `{a='report', c, n, room, why, txt, who}` with `txt` at most 300
  bytes and `who` (the reported player first) at most 25 names, trimmed until
  the JSON fits 2048 bytes. One report at a time (10 s, or until `rep`); a
  `rep` with no report pending is ignored. The text goes as typed (Latin-1),
  like `game_feedback`.
- **Speaking**: rings in the rows and the over-head icon change only on edges;
  the over-head icon is attached only to a creature that exists, is not dead
  and has a position, at most 8 at a time, and is destroyed on the off edge
  (destroying it detaches it). `speakers` 0 removes every icon but our own.
  Our own voice coming back from the echo room gets no second icon (the
  local gate's `self` icon is there). Every icon is destroyed on the off
  edge, when the speaker leaves our rooms, and at game end.
- A member row that leaves a room with hidden members gives its place to a
  hidden one in a redraw at most once a second, so a big room's churn does
  not redraw the panel every frame.
- **Ducking**: game channels go to 70% on the first speaker and back on the
  last; a volume the player changed meanwhile is kept.
- **Push-to-talk**: the three talk keys, mute, deafen and the panel toggle are
  `Keybind` actions of the `Voz` category (no default key; Options > Hotkeys
  lists them once voice was offered). A key that types in the chat is refused
  while the chat is on, and saved for "chat off" only when the chat is off.
  A key is also refused when anything else would run on it in the chat modes
  it is saved for (`VoiceSettings.keyTaken`): another `Keybind` action, a
  hotkey of the current preset, the hotkeys manager (`game_hotkeys`) or an
  action bar button (`game_actionbar`); in the browser, F11 (the page's full
  screen). A key the client has no name for cancels the capture.
  Release: the key-up of the same combo, any key-up of that key (another
  modifier held), focus loss (the window releases every key), and a 60 s limit
  with a notice. Touch screens get a hold-to-talk button.
- **Preferences** (`g_settings` node `voice`), per installation: `onboarded`,
  `mode`, `vadDb`, `inGain`, `outVol`, `preset`, `autoParty`, `autoGuild`,
  `overheadIcon`, `ducking`, `globalPtt`, `pttMouse`, `selfMuted`, `deafened`,
  `inDevice`, `outDevice`, and `users` = `{ g<guid> = { v = 0-200, m = bool, t = unix } }`
  (string keys: OTML loses numeric ones). An entry back at the defaults is
  dropped; at most 500, least recently changed go first. Saved once a second
  at most (sliders).
- **The opt-in is per character** (`chars` = `{ <character name> = { t = unix } }`,
  at most 100): the plan kept one `enabled` per installation, but on a shared
  computer the next player's character would then join the party room and
  hear it without having turned voice on. The panel's position and open
  state are per character too (`CharMiniWindows`, the MiniWindow default).
- **Translations**: `voice_locale.lua` only fills keys `pt.lua` lacks, so a
  common word ("Other", "None", "Offense") keeps the meaning other windows
  give it; the report reasons and the mouse option use their own English
  keys ("Insults", "Other reason", "No side button"). A test checks that every
  key both files define has the same text.
- The rules link in the onboarding points to `https://mythosot.com.br/?subtopic=voz`
  (to be created with the rules text).

## Known gaps for later phases

- Mouse side buttons in the native client (phase 7) and real audio (phases
  4 and 6). "Testar microfone" calls the engine's local loopback; the relay's
  echo room is the "Teste de eco" entry of the room list.
- The over-head icon offset (`VoiceHeadIcon` margins) is a first guess and
  must be checked on screen with the CI browser build.
