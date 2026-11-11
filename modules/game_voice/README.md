# game_voice (Mythos Voz)

Voice chat in the game panel: the party room, the guild and officers rooms,
public rooms and event stages, Discord-like, and proximity ("Perto de você":
who is on your screen hears you, quieter with distance and panned left or
right; see Proximity below). Audio goes through the
`mythos-voz` relay (Go, `tools/voz` in the server repository); canary only
grants the rights, over extended opcode 142.

This module is phase 3 of the voice plan: the whole panel and protocol with
the **mock** and **lite** engines. The **full** engine (real audio) runs over
the `g_voice` C++ binding: in the browser build since phase 4
(`browser/voice/mythos-voice.js`, WebCodecs and AudioWorklet; see
`browser/voice/README.md` for the engine and its tests). The Windows build
has no `g_voice` until the native engine (phases 6 and 7), so there
`EngineFull.available()` is false and the lite engine is used.

## Files

| File | What it holds |
|---|---|
| `voice_state.lua` | The pure part: state machine, opcode 142 and relay messages, rooms and members, control rate limit, preferences, report builder, the near list and the spatial values with their timers. No `g_*` call and no widget: it runs in plain LuaJIT (the map is read through `io.nearby` and `io.offset`, which voice.lua gives). |
| `engine_full.lua` | Thin wrapper over `g_voice` (only if the binding exists and `isSupported()`). |
| `engine_lite.lua` | Control messages only, over `HTTP.webSocket`: presence, rooms, moves, moderation. No audio. |
| `engine_mock.lua` | A relay inside the client (welcome with proximity, a roster of 4 made-up players, near with 3 more and a passer-by who walks in and out, speaking edges every 1-3 s), plus canary's opcode 142 answers. |
| `voice.lua` | The glue: opcode 142, engine choice, push-to-talk keys, ducking, game start/end, the map reads of proximity. |
| `voice_ui.lua`, `voice.otui` | The panel, member rows, right-click menus, volume popup, report window, over-head icon. |
| `voice_settings.lua`, `voicesettings.otui`, `voiceonboard.otui` | Settings window and the one-time onboarding. |
| `voice_locale.lua` | Portuguese for every English string (Latin-1 as `\ddd` escapes), merged into the `pt` locale on first use, only for keys `pt.lua` lacks. |
| `images/` | Icons, pixel art in the client's palette (the `game_brevespanel` icons: ink outline `#090a10`, gold `#705035/#c99c53/#ffe0a0`, silver `#5b4d6a/#a99eb4/#e9dec7`, the panel's green and red): 16x16 header buttons, 12x12 member icons, the 18x16 over-head speaker, the 40x20 top-menu toggle (it sits in the right panel's grid of stock buttons, so it is drawn like them: `data/images/options/button_empty`'s stone frame and a flat `#c9c9c9` glyph, the right half pressed/on with the glyph 1 px down and right), the 48x48 touch button. Drawn by `tools/voz-luatest/icons_gen.py` (Python 3 with Pillow; kept out of the module so it does not ship): `python3 tools/voz-luatest/icons_gen.py modules/game_voice/images data/images/options/button_empty.png` from the repo root rebuilds all 17 files. |

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
| `mic` | `s` = `ok`, `denied`, `nodevice`, `encoder` (the browser or the native engine could not encode: listen only; `denied` and `encoder` show a notice) |
| `devices` | the device lists changed |

Contract for the phase 4/6 `g_voice` binding, used by `engine_full.lua`:
`connect(url, token, clientTag, build)` sends the hello itself once open;
`disconnect()`, `sendControl(json)`, `setTransmit(slot|-1)` (slots 0-3),
`setMode(vad)`, `setVadThreshold(db)`, `setPreset(0 normal|1 eco|2 high)`,
`setInputDevice(name)`, `setOutputDevice(name)`, `getInputDevices()` and
`getOutputDevices()` (arrays of names), `setInputGain(x)`,
`setOutputVolume(x)`, `setUserVolume(sid, x)`, `setSlotVolume(slot, x)`,
`setDeafened(b)`, `setSelfMuted(b)`, `setMeter(b)`, `setPttMouse(btn, slot)`
(browser; btn 3 or 4, slot -1 to turn off), `setGlobalPtt(vk)` (Windows; a
virtual-key code, 0 to turn off), `startLocalTest(b)`, and with the slot-3
engines `setUserSpatial(sid, gain, pan)` (gain 0-1, pan -1 left to 1 right,
for that speaker's slot-3 frames only). `EngineFull.create` looks that one
up once with a type test: an older executable has none, `engine.spatial` is
false and the session never computes a spatial value (the lite engine has
none either; the mock keeps the values). The wrapper drops a
`closed`/`error` state that arrives after its own `disconnect()`.
`applyEnginePrefs()` sends every setting again on each change (each slider
step), so a setter whose value did not change must do nothing: no microphone
reopened by `setInputDevice`, no permission prompt from `setMeter` (the
browser engine opens the microphone for the meter only when the permission is
already given; a press or the mic test opens it otherwise). Behaviour the
native engine must match (listed in `voiceengine.h`): voice activation
listens only in a room; the side mouse button and the push-to-talk key are
held apart; whatever needs the capture wakes an output stream asleep from
idle; a saved device unresolved at the first open is moved to once it can
be; `disconnect()` keeps the meter going while `terminate()` stops it.
voice.lua ends the mic test in the engine too (`startLocalTest(false)`)
whenever the session leaves ONLINE or the game ends: the engine does not end
a test because the relay closed the socket.

## State machine (`voice_state.lua`)

```
OFF --game start--> WAIT_CFG --cfg off--> DISABLED (beta/off/bad url, invisible)
                       |                  BLOCKED banned (the panel shows the date; no onboarding)
                       +--cfg on--> READY --"Turn voice on"--> WAIT_TOKEN
                       +--cfg on and this character opted in -> WAIT_TOKEN
WAIT_TOKEN --tok--> CONNECTING --welcome--> ONLINE
CONNECTING/ONLINE --close--> see below
BACKOFF/FAILED --timer--> CONNECTING (fresh unused token) or WAIT_TOKEN (asks one)
BACKOFF/FAILED --tok or cfg on from canary--> the same, at once
any --game end--> OFF
```

| Close | Action |
|---|---|
| 4401 | ask `{a:'tok'}` once, at once; a second 4401 before 30 s online backs off |
| 4403 | BLOCKED banned |
| 4409 | BLOCKED replaced ("Reconectar" button, no automatic retry; a later `cfg on` does not lift it either, or two windows would replace each other forever) |
| 4503 | BLOCKED off |
| 1012 | BACKOFF 1-5 s random, not counted as a failure |
| 4429, 4408, 1000, network, unknown | BACKOFF 1, 2, 4, 8, then 15 s ±30%; from the 20th failure in a row (about 4 minutes) FAILED, which still tries by itself every 60 s ±30% ("Tentar de novo" tries at once) |

The failure count (and the one-time 4401 retry) resets after 30 s online.
No token within 10 s, or no welcome within 15 s of connecting, counts as a
failure. Backoff and every other wait use `scheduleEvent`; nothing per frame.
The steps stop at 15 s so a relay back after an outage is found within 20 s
(the play-test: 40 s after a one-minute outage with steps up to 60 s), and
FAILED never needs a click: a relay restart or a VPS reboot of a few minutes
used to leave every player without voice until each one pressed the button.
A token canary pushes (or a late answer) and a `cfg on` while waiting in
BACKOFF or FAILED are a sign the server is there: the retry is made at once
(with the token, or the new relay address). Token requests keep canary's
limits all along (see Tokens below); the panel counts down to the next try
in both states.

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
- **Slots**: 0 party, 1 guild or officers, 2 a public room, event or the echo
  test, 3 near (proximity). Every walk over the slots (rooms, members,
  speaking, mutes, intents, the talk keys, the touch button, the own ring)
  goes to `VoiceState.LAST_SLOT`.
- **Rejoin after a reconnect**: the party room comes from the token (autoParty),
  the guild/officers room is joined again only if the token still lists it,
  the public room or event of before is joined again (the relay refuses it
  with `err room_denied` if the rights changed, which clears it), and near
  with autoNear, or when it was joined by hand before the drop.
- A party or guild room left by hand is not auto-joined again until its id
  changes (a new party epoch); near left by hand, not in this login (a join
  by hand lifts it).
- **Control rate limit**: the relay allows 5/s, burst 10; this client sends at
  most 4/s after a burst of 8, through a queue of 256 (one `mute` for each
  muted player of a big guild roster; the relay keeps up to 256). A newer
  `mute` for the same player, `self`, `deaf`, `dir`, `auth` or `near`
  replaces the pending one. A saved mute or volume is sent once per player
  and relay session, even when the player is in two of our rooms.
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
  show unless staff; in near only the staff has them (no party-leader or
  guild moderation there). The relay checks every action again.
- **Reports**: `{a='report', c, n, room, why, txt, who}` with `txt` at most 300
  bytes and `who` (the reported player first) at most 25 names, trimmed until
  the JSON fits 2048 bytes. One report at a time (10 s, or until `rep`); a
  `rep` with no report pending is ignored. The text goes as typed (Latin-1),
  like `game_feedback`.
- **Speaking**: rings in the rows and the over-head icon (near speakers too)
  change only on edges; the over-head icon is attached only to a creature
  that exists, is not dead and has a position, at most 8 at a time, and is
  destroyed on the off edge (destroying it detaches it). `speakers` 0
  removes every icon but our own.
  Our own voice coming back from the echo room gets no second icon (the
  local gate's `self` icon is there). Every icon is removed on the off
  edge, when the speaker leaves our rooms, and at game end. The icon is an
  image the engine draws with the creature (an attached effect, id 65021,
  registered once per client run), not a widget attached to it:
  `Map::updateAttachedWidgets` reads `g_drawPool.getScaleFactor()` while no
  draw pool is selected (`m_pools[LAST]`, one past the end), which in the
  browser left such a widget at the tile's corner (10 px left of the name)
  and in a 64-bit desktop build reads through a wild pointer. The effect
  follows the walk and the jumps and goes with the creature. Its offsets
  (sprite px, from the outfit's displacement and the map's tile size, found
  by asking `UIMap:getPosition` where the drawn map starts and ends) centre
  it over the name, 9 screen px above the creature's point; in the map's
  top rows, where it would leave the drawn map (letterboxed in the classic
  view), under the feet. Shown only while the name is (`UIMap:isInRange`:
  the camera's floor, inside the view). A speaker's moves, appear,
  disappear and death, and our own moves, check the icons once on the next
  frame (`UI.placeHead`); no check runs while nobody talks.
- **Member rows**: the 12 px icons are phantom; the row's tooltip says each
  in words ("Membro da equipe", "Microfone desligado", "Áudio desligado",
  "Silenciado pela equipe", "Silenciado para você", presence mode). The
  header's switches use the same words: "Desligar/Ligar microfone",
  "Desligar/Ligar áudio". Online, the status row and the Voz button say
  "Conectado" (it said "Voz" under the title "Voz").
- **Settings keys**: label 92 px ("Na sala/evento", as the Hotkeys list's
  "Falar na sala/evento"; "Perto de você" is 82), then the key box, 126 px
  in the client, which shows "Aperte uma tecla..." and keys up to
  "Ctrl+Shift+PageDown" whole; the box's tooltip has the key whole. The
  window is 466 px high for the fourth key row and the autoNear check box
  ("Entrar sozinho em Perto de você", 193 px after the box's 18). The Lua
  test measures these with the font's glyph widths.
- A member row that leaves a room with hidden members gives its place to a
  hidden one in a redraw at most once a second, so a big room's churn does
  not redraw the panel every frame. In near (people walk past all the time)
  a hidden member takes the free row in place: near's `in` and `out` never
  redraw the panel.
- **Where the panel opens** (`VoiceUI.toggle`): where it is if its side panel
  has room for its minimum height; else a side panel with room
  (`findContentPanelAvailable`); else the top of the selected side panel
  (the play-test at 1280x720 with Battle List, Unjustified Points and VIP:
  appended at the end, it opened under the bottom of the screen). 100 ms
  later, once the layout settled, a panel that does not end inside
  `rootWidget` floats over the top right of the map (and is saved there).
- **Section headers**: "SUA PARTY", "SUA GUILD", "PERTO DE VOCÊ", "SALAS",
  "EVENTOS" (the client says "party" and "guild": the bosses window's "Sua
  party", pt.lua's "Entrar na party do %s"; a bare "PARTY" read as English).
  "PERTO DE VOCÊ" (99 px bold) and "Entrar" (50 px) fill the 150 px header
  with 1 px to spare, so its key hint shows only in its tooltip. The key hint
  ("Segure Insert") ends where the header's button (Sair, Entrar, Mostrar)
  starts; when it does not fit, only the key shows ("Insert"), and when not
  even the key fits, nothing (a cut "Segure I..." read as a broken label).
  The header's tooltip has it whole.
- **Volume popup**: a click on the track or an arrow moves 10% (it moved 1%),
  on the 10% grid for the track; "0%" and "100%" buttons; the thumb still
  drags freely.
- **Ducking**: game channels go to 70% on the first speaker (near ones too)
  and back on the last; a volume the player changed meanwhile is kept.
- **One place to talk (2026-11-11)**: voice activation is the default
  (`mode` 'vad'; `modeV` 1 moved every saved 'ptt' of before to it once).
  Voice activation, the one talk key "Falar", the browser's side button and
  the Windows background key all talk in the same place,
  `Session:targetSlot()`: the party; else the guild or officers; else the
  room or event; else near you. A player who does not want to be heard
  mutes the microphone or leaves the room. "Falar" took the key of the old
  "Falar na party" (`migrateTalkKey`); the other per-room keys are gone.
  The panel shows "Segure X" only next to the section the key talks in, and
  only in push-to-talk.
- **Push-to-talk**: the talk key "Falar", mute, deafen and the panel toggle
  are `Keybind` actions of the `Voz` category (no default key; Options >
  Hotkeys lists them once voice was offered). A key that types in the chat is refused
  while the chat is on, and saved for "chat off" only when the chat is off.
  A key is also refused when anything else would run on it in the chat modes
  it is saved for (`VoiceSettings.keyTaken`): another `Keybind` action, a
  hotkey of the current preset, the hotkeys manager (`game_hotkeys`) or an
  action bar button that holds an action (`game_actionbar`: the bar puts
  F1-F12 on its first buttons, and the key of an empty button is free; a
  button with a rune the character has none of yet, or a spell it cannot
  cast yet, still counts: its key will run it); in
  the browser, F11 (the page's full screen). A key the client has no name for
  cancels the capture, and so does Escape. The box keeps the keyboard until
  the press that follows the key's down, and eats it: Escape or Enter there
  reached the window and closed it (the onboarding as seen for good with
  voice off). The onboarding offers a free key when the party has
  none (`VoiceSettings.freeKey`: Insert, else Pause), set only when voice is
  turned on there; in the browser with the full engine it also offers the
  mouse side button (Mouse 4). A refused key names a free one ("Tente
  Insert."); the chat-key hint no longer suggests F1-F12.
  Release: the key-up of the same combo, any key-up of that key (another
  modifier held), focus loss (the window releases every key), and a 60 s limit
  with a notice. Touch screens get a hold-to-talk button.
- **Preferences** (`g_settings` node `voice`), per installation: `onboarded`,
  `mode`, `vadDb`, `inGain`, `outVol`, `preset`, `autoParty`, `autoGuild`,
  `autoNear` (default on), `overheadIcon`, `ducking`, `globalPtt`, `pttMouse`,
  `selfMuted`, `deafened`,
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
  key both files define has the same text, that no string the module shows
  keeps its English text in Portuguese (only "Spam", "Normal", "Volume",
  "Mouse 4/5" are spelled the same), and walks the panel, its menus, the
  report window and the settings drawn in Portuguese for English left over.
- The rules link in the onboarding points to `https://mythosot.com.br/?subtopic=voz`
  (to be created with the rules text).

## Proximity ("Perto de você", slot 3)

The relay has one `near` room (kind `near`, slot 3) when its config enables
it; who hears whom is mutual visibility: A and B are near when both are in
the room and each one's latest list holds the other's creature id. Audio on
slot 3 goes only to the members near the speaker.

- **Welcome**: `"near":{"lvl":N}` when the relay has it (`session.near =
  { lvl = N }`, N the level to talk there, read through `VoiceState.num`).
  Absent, the client shows nothing of it and joins nothing.
- **Joining**: with `autoNear` (on by default) near is joined after every
  welcome, like the party room; not when the player left it by hand in this
  login (`optOut[3]`, lifted by a join by hand), nor after an `err` that
  refused the join (`room_denied`, `kick_block`) or a `left` (kicked, or
  switched off on the relay) until the next welcome. A `room_denied` while
  in near is a talk spurt under the level: the room stays and the player is
  told "Voz: para falar perto você precisa do nível N.". Lite sessions join
  too (presence only).
- **The near list** `{"t":"near","c":[cid,...]}`: while the session is in
  near, every 500 ms (the session's `near` timer, scheduleEvent), voice.lua
  asks `g_map.getSpectatorsInRange(pos, false, 7, 5)` around the local
  player and `VoiceState.nearList` keeps the players on its floor within 7
  tiles left or right and 5 up or down, alive with a position, never the
  local player, nearest first, at most 40. It is sent only when the set
  changed (the sorted ids; the nearest walking changes nothing), at most
  once per 500 ms, and once right after the near roster arrives (500 ms
  after the last list at the earliest). A map read that fails keeps the last
  list (logged once).
- **Spatial values** (off since 2026-11-11, `VoiceState.SPATIAL = false`:
  near voices sounded odd with distance and pan; they now play like any
  other, and the timer never starts): every 200 ms (the `spatial` timer) while someone in
  near talks, and at once on a near member's speaking edge (or when one
  already talking in the party comes near), each talking near member but us
  is looked up by its creature id: missing, dead or on another floor ->
  gain 0, the pan kept; else `d = sqrt(dx^2 + dy^2)` tiles, gain =
  `clamp(1 - max(0, d - 1.5) * 0.11, 0.2, 1)`, pan = `clamp(dx / 7, -1, 1) *
  0.75`. `setUserSpatial` is called only when gain or pan moved by more than
  0.02 (at most 5 calls a second a speaker). The engine applies it to that
  speaker's slot-3 frames only: a party member who is also near sounds
  centred in the party. The timer stops at the first tick with nobody near
  talking.
- **Cost**: nothing runs when the session is not in near: both timers start
  from the near roster, stop when near is left (by hand, `left`), on any
  drop of the relay session and at game end (`dropConnection`, `gameEnd`),
  and the spatial one runs only while a near member talks and the engine can
  pan (`io.canSpatial`). A member who walks out of sight (`out`) is
  forgotten with its speaking state (unless it is in another of our rooms)
  and its spatial values; nothing is sent to the engine for it.
- **Panel**: "PERTO DE VOCÊ" after the guild and before the rooms, with
  Entrar/Sair, "Segure X para falar perto" while near is where the key
  talks (push-to-talk only), the members near us from the roster, `in`
  and `out` (in place, never a redraw) and, while the character's level is
  under N, the note "Falar perto: nível N+" (read when the panel is drawn).
  Settings: one key row ("Falar") with the order it talks in, and "Entrar
  sozinho em Perto de você" (autoNear).
- **Mock**: `voice-mock` shows near with three made-up players (creature ids
  `0x10FFFF01`..`03`, which no creature has: no icon, gain 0) whose speaking
  toggles, and a passer-by who walks in and out.

## Known gaps for later phases

- Mouse side buttons in the native client (phase 7) and real audio in the
  Windows client (phase 6). "Testar microfone" calls the engine's local
  loopback (in the browser: microphone -> Opus -> mixer, nothing sent); the
  relay's echo room is the "Teste de eco" entry of the room list.
- The over-head icon is checked in the browser build (classic view, tiles
  of 41 and 48 px). A window resize while someone talks moves it at the
  speaker's next step or speaking edge. Once `Map::updateAttachedWidgets`
  takes the map's own scale factor (`mapView->m_posInfo.scaleFactor`), an
  attached widget would work too; the effect does not depend on it.
- The Hotkeys list still names the mute and deafen actions "Silenciar
  microfone" and "Ensurdecer" (`KEY_MUTE`, `KEY_DEAFEN` in `voice.lua`, the
  saved keybind names); the buttons now say "Desligar microfone" and
  "Desligar áudio".
