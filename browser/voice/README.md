# Mythos Voz in the browser: `mythos-voice.js` and the `g_voice` bridge

The browser client's voice engine. The Lua panel (`modules/game_voice`) talks
to `g_voice`; in the WASM build `g_voice` is `src/framework/voice/` with the
web engine, which hands everything to this script in the page. The relay is
`tools/voz` in the server repository (protocol: `README.md` there).

## How it fits together

```
Lua (game_voice/engine_full.lua)                       page main thread                    audio thread
  g_voice.setTransmit(0) ─► VoiceManager ─► WebVoiceEngine ─MAIN_THREAD_ASYNC_EM_ASM─► MythosVoice.cmd({"op":"tx","slot":0})
                                                                                         │  mic ─► mv-capture (gate, 40/60 ms frames)
                                                                                         │  AudioEncoder (Opus) ─► WebSocket [01|flags|seq|opus]
  g_voice.onVoiceEvent(type, s, a, b) ◄─ poll() ◄─ inbox ◄─ Module._otc_voice_event ◄─── events, one JSON batch per microtask
                                                                                         │  WebSocket ─► AudioDecoder per speaker ─► mv-mixer (jitter buffer,
                                                                                         │                      gains, near speakers' places, limiter) ─► speakers (stereo)
```

- **No new file to download.** `cmake/VoiceShell.cmake` pastes
  `mythos-voice.js` into a copy of `browser/shell.html` at the marker
  `<script>/*MYTHOS_VOICE*/</script>`, and the WASM link uses that copy as
  `--shell-file`. `navegador.yml`'s upload list and `ativar-navegador.sh`
  stay as they are. The source is 75 KB (22 KB gzipped), mostly comments.
  The CI links at -O2, and at -O1 and up emscripten's link step runs
  html-minifier-terser (with terser for inline scripts) over the finished
  page (`MINIFY_HTML`, after the shell was preprocessed), so the shipped
  index.html most likely carries the engine minified: about 31 KB, 12 KB
  gzipped. `test/lint.mjs --minify` repeats that step with emscripten's
  flags and runs the tests on the result (not checked against a real emcc).
- **The game thread never waits on the page.** Commands go out with
  `MAIN_THREAD_ASYNC_EM_ASM` (a malloc'd copy, freed by the page with the
  exported `_free`). Events come back through the exported
  `otc_voice_event`, which only copies the text into a mutex-guarded inbox;
  `VoiceManager::poll()` (game thread, next to `g_sounds.poll()`) parses it
  with nlohmann-json and raises at most 64 events per frame. The only
  synchronous call is `isSupported()`, once, until the page has an answer.
- **A game thread that stops polling** (a hidden tab stops its frames, and
  voice goes on): the inbox takes 1024 batches, then `otc_voice_event`
  returns 0 and the page keeps the batch and tries again every 250 ms. Its
  own queue then holds 512 events; past that it drops levels, stats and all
  but the last `talk`, and if that is not enough it ends the connection
  itself and queues one `state closed 1006` of that generation, keeping the
  newest `mic`, `devices` and `caps`. The game, polling again, takes the
  old events, then the `closed`, and joins again from a fresh welcome
  instead of living with a gap (a lost `closed` would leave it online with a
  dead socket, a lost `spk` off a speaking ring on). `VoiceManager` still
  takes `state` events past its own 4096.
- **Generations.** Every `connect` carries a number the page echoes on that
  socket's events; the C++ drops events of a socket it replaced or closed,
  so a late `closed` never ends a newer connection. A socket closed by
  `disconnect` or replaced by `connect` reports nothing at all.
- **The page never crashes the game.** `shell.html` shows its crash screen
  on any uncaught error; every callback of the engine goes through `safe()`
  (errors are counted in `MythosVoice.stats().errors`).
- **Desktop:** `TOGGLE_FRAMEWORK_VOICE` defaults ON only in the WASM build.
  The Windows build compiles none of this (the preprocessed
  `luafunctions.cpp` and `graphicalapplication.cpp` are byte for byte the
  same as before), so `g_voice` is absent and Lua uses its presence-only
  engine. Turned on by hand on desktop it builds `voiceengine_null.cpp`
  (`isSupported()` false). The native engine (libopus, OpenAL) implements the
  same `VoiceEngine` interface later; `voiceprotocol.h` is its framing.

## The engine (`mythos-voice.js`)

| Part | What it does |
|---|---|
| Support | At load: WebCodecs Opus encode and decode at 48 kHz mono, AudioWorklet, secure context. `support()` is 1, 0, or 2 while the codec query runs. `opus.signal='voice'`/`application='voip'` are used when the browser keeps them. |
| AudioContext | One, 48 kHz, `latencyHint: 'interactive'`, made on the first need (connect, microphone, meter). Closed on `disconnect`. **Sleeps** (`suspend()`) after 15 s with nothing heard or captured (push-to-talk idle, no mic test, meter, voice activation or mouse button in use). Woken by the next incoming frame and by every use of the microphone: all of them (push-to-talk key or mouse button, mic test, meter, switching to or unmuting voice activation, a microphone that opens after a long prompt) go through `ensureMic()`, which wakes it, and the 1 s housekeeping wakes it too whenever something is in use while it is not running (the capture worklet does not run in a suspended context). Starting and waking: the "Jogar" click gives the page sticky activation, so in Chrome `resume()` works from anywhere. When a wake is due and the context still does not run (made before any press, or a browser that starts audio only inside a press, as WebKit may), the next trusted pointerdown or keydown calls `resume()` itself, even with an earlier `resume()` still pending (Blink keeps those pending until audio starts). A key alone never wakes a context that sleeps on purpose. If a `resume()` outside a press has not started audio after 2 s, the engine stops putting the context to sleep for the rest of the page (asleep, an incoming voice could not wake it there). |
| Microphone | `getUserMedia` with the browser's echo cancellation, noise suppression and gain control. Unused, it stays open 5 min while connected (the next press starts at once) and 30 s once not connected for 30 s (a reconnect's backoff keeps it). It is asked for only by a press (push-to-talk, the mic test) or by voice activation, which the player chose. The level meter (on while the settings window is open) opens it only when that brings up no prompt: the Permissions API says `granted`, or a stream was open on this page before. Otherwise the meter shows the level once a press opens the microphone, so opening the settings window never pops up the browser's prompt (which can drop fullscreen). Refused: event `mic denied` (listen-only), asked again at most every 5 s. None or busy (`mic nodevice`): asked again when a device appears (`devicechange`), and every 15 s while voice activation needs it. Voice activation: open while connected, in a room and not self-muted (self-mute stops it unless the meter or the test still uses it; in no room nothing is captured, sent or shown as talking). Device by name; a vanished one falls back to the default. Only a real device change reopens it. A browser that lists no labels before the permission (Chrome without a stored one, Firefox) cannot resolve a saved name on the first open: the default device opens, and once the list shows labels the microphone moves to the saved one, once (`stats().micMoves`). The meter survives a `disconnect` (the settings window may still be open); `disconnect {end: true}` (the game closing) stops it. |
| `mv-capture` | Frames of 1920 (40 ms) or 2880 (60 ms, eco) samples at 48 kHz (linear resampling for a context at another rate). Gate: push-to-talk, or voice activation (threshold, -6 dB hysteresis, 300 ms hangover, 1 frame of pre-roll). Posts frames only while the gate is open, the last one marked END; a level every 100 ms only while metering. Does nothing while idle. |
| Encoder | `AudioEncoder` Opus, CVBR, complexity 5, no DTX, no FEC; 16 kbps/40 ms (normal), 12/60 (eco), 24/40 (high). A preset change applies from the next spurt. At load, `isConfigSupported` is asked for all three presets; a refused one encodes as normal. An encoder that fails before its first frame: eco or high is then dropped for the page (the capture switches to 40 ms frames at once, `caps` is sent again); a failing normal is retried at most every 2 s, with one `mic encoder` event (the panel says it can still listen) until a frame comes out. An encoder the browser reclaims (`QuotaExceededError`) or that fails after working is only replaced. Up: `[0x01][slot|END<<2|VAD<<3][seq]` + Opus (1-240 B, or the welcome's `lim.pl` if lower: the relay counts bigger ones as abuse); not sent for a slot with no room (`up.noRoom`); dropped while the socket has a 16 KB backlog. |
| Receive | AUDIO and BUNDLE; speaking edges (on: first frame over 10 B; off: END or 300 ms without frames, checked every 100 ms only while someone speaks). One `AudioDecoder` per speaker, at most 8 (least recently used go), freed after 10 s idle; a decoder that fails sits out 1 s. Deafened: nothing decoded. |
| `mv-mixer` | Per speaker, protocol I: start at 80 ms buffered or 120 ms after the first frame (both grow with J), frames by u8 seq (wrap), J = moving average (1/16) of the arrival jitter, target clamp(80+2J, 80, 240) ms, a missing frame is a 10 ms fade then silence (at most 3, then wait), late frames dropped, reset at END. Over 400 ms buffered, or a TCP stall's backlog (2+ frames over the target with no frame for 10 ms), the oldest frames go down to the target. Gain = speaker x slot x master (0-2), the slot being the one of the frame played (every frame keeps its own); soft limiter; deafened outputs only its own microphone test. Stereo out (`outputChannelCount [2]`): every voice is centred, left = right, the same samples the mono mix had (mixed into the left channel and copied to the right once per block, so no extra work per voice). A speaker's frames on slot 3 (near) once the game gave it a place (`spatial`): gain 0-1 times the rest, constant-power pan scaled so that pan 0 at gain 1 is exactly a centred voice (left, right = g·√2·cos, g·√2·sin of (pan+1)·π/4: +3 dB on one side at pan ±1, the same total power): its left part goes into the left channel and right − left into one scratch block (made once), added to the copy for the right; a new place while that voice plays moves there in a 50 ms linear ramp per sample, otherwise at once. A one-channel output (never made) gets half of left + right. |
| Push-to-talk extras | Window blur and a hidden tab release it (`talk -1`). Side mouse buttons 4/5 (`pttMouse`, DOM buttons 3/4): mousedown/mouseup in the capture phase with `preventDefault`, `auxclick` prevented (no Back/Forward), 60 s limit. The key (`tx`) and the button are held apart: while the button is held it talks on its slot, and letting go gives the key's slot back (a key still held goes on talking); letting go of the key while the button is held keeps the button's. |
| Output device | `AudioContext.setSinkId` where it exists (Chrome/Edge 110+); elsewhere the output list is empty and the panel disables it. A saved name is applied whenever a device list resolves it (Chrome shows output labels only after a microphone permission, so a listen-only player keeps the default output). |
| Test | `test` loops the microphone through the encoder and decoder into the mixer as speaker 65536, outside the relay's sids (1-65535, u16 on the wire); nothing goes to the relay. |

Commands (`MythosVoice.cmd`, JSON text from C++ or an object): `connect {url,
tok, cl, b, g}`, `disconnect {end}` (`end` from `terminate()`: the meter stops too), `ctl {json}`, `tx {slot}`, `mode {vad}`,
`vad {db}`, `preset {p}`, `mic {on}`, `indev {id}`, `outdev {id}`,
`ingain {x}`, `outvol {x}`, `uvol {sid, x}`, `svol {slot, x}`,
`spatial {sid, g, p}` (a near speaker's place for its slot-3 frames: `g`
0-1, `p` -1 left .. 1 right, clamped, defaults 1 and 0; a repeated value does
nothing; forgotten with the connection, as `uvol`), `deaf {on}`,
`smute {on}`, `meter {on}`, `pttMouse {btn, slot}`, `test {on}`, `stats`,
and `probe {on}` (tests: onset timestamps and output RMS, `rms` left and
`rmsR` right). Slots are 0 party, 1 guild/officers, 2 public/stage/echo and
3 near (proximity) everywhere: `tx`, `svol`, `pttMouse`, the rooms tracked
from `roster`/`moved`/`left`, frames up and down. Voice activation talks in
the first room joined, 0 to 3 (party, guild, room, near): the same place as
the game's one talk key.

`voice.lua` sends every setting again whenever one changes (each slider step,
each checkbox), so a setting command whose value did not change does nothing:
`indev` reopens the microphone only for another device, `mode`, `deaf`,
`smute` and `meter` act only on a change. The native engine of phase 6 must do
the same (`voiceengine.h` says so).

Events (to `Module._otc_voice_event`, or to `MythosVoice.setSink(fn)`):
`state {s: connecting|open|closed, a: close code, g}`, `ctl {s: relay text,
g}`, `spk {a: sid, b: 1|0, g}`, `talk {a: slot|-1}`, `level {a: dBFS}`,
`mic {s: ok|denied|nodevice|encoder}`, `devices {i: [names], o: [names]}`,
`stats {s: JSON}`, `caps {s: JSON: ok, hints, sink, presets [1, eco, high]}`. The C++ turns them into
`g_voice.onVoiceEvent(type, s, a, b)` and keeps the device lists for
`getInputDevices()`/`getOutputDevices()`.

Rules for the file (checked by `test/lint.mjs`, enforced by CMake for the
first two): no three braces in a row and no `</script`, no line starting
with `#` (emscripten preprocesses the shell and takes those as directives),
no backtick strings.

## Tests

From `browser/voice/test/`:

| Command | What it checks | Needs |
|---|---|---|
| `node lint.mjs [--browser] [--minify]` | the rules above; `cmake -P cmake/VoiceShell.cmake` writes the page byte for byte; the page has no preprocessor directive; with `--browser`, the pasted page defines `MythosVoice` in Chromium next to `Module`; with `--minify`, the page minified as emscripten's link does it (html-minifier-terser with emscripten's flags), its engine written to `tmp-min/mythos-voice.js`, and `worklet.mjs` and `bridge.mjs` run on that copy | node, cmake (Playwright for `--browser`; for `--minify`, html-minifier-terser 7.2.0: `MV_MINIFIER=<its package folder>` or `npm install --no-save html-minifier-terser@7.2.0`) |
| `node worklet.mjs` | 61 unit checks of `mv-mixer` (protocol I: start, reorder and wrap, concealment, late, 400 ms cap and stall backlog, END, J, gains, deafen incl. sid 65535, limiter, 44.1 kHz; stereo: centred voices left = right sample for sample; the near room: slot 3 with no place as slot 0, pan -1/+1/0.5 and gain 0.5 with constant power, master x slot 3 x user x spatial gain, a place leaves slots 0-2 alone, a slot change inside a spurt heard when its frames play, the 50 ms ramp while talking and at once between spurts, deafen, the limiter on the right, kept across a decoder drop and forgotten on reset, 44.1 kHz, probe levels per side, no Float32Array made per block with a placed voice playing) and `mv-capture` (push-to-talk and END, voice activation hysteresis/hangover/pre-roll, presets from the next spurt or at once, meter, resampling, slot 3 by key and by voice activation), in Node | node |
| `node bridge.mjs` | 46 checks (45 on the minified copy, which skips the three-braces text check) of the page side of the C++ bridge with a fake emscripten `Module` and WebSocket: nothing before the first command, one batch per microtask, UTF-8, big rosters through `_malloc`, every buffer freed, the hello, AUDIO/BUNDLE parsing, speaking edges, generations, replaced/closed sockets silent, close codes, no self-reconnect, the welcome's `lim.pl`, the push-to-talk key and the mouse button held together, the near room (roster on slot 3, key and mouse button on slot 3, `svol 3`, frames on slot 3, `spatial` clamped and kept per sid, forgotten with the connection), a full inbox (refused batches kept and delivered in order; a long stall ends the connection with one `closed 1006`, the newest `mic` kept) | node |
| `node e2e.mjs [--only ptt,vad,...] [--json out.json]` | two Chromium pages (A talks, B listens) and vozbots through a local relay it starts on 127.0.0.1:7291 (page server 127.0.0.1:8291): frames, END, speaking edges, output RMS, Opus size, mouth-to-ear latency, vozbot (libopus) decoding the browser's Opus, voice activation, self-mute, mute-for-me and deafen at the relay, blur, side mouse button, mic test, setting bursts (a slider drag) that must not reopen the microphone or cut a spurt, eco preset, last-N with 5 talkers, CPU and heap, idle sleep and wake by an incoming voice, the near room when the relay has it (the welcome's `near`: A and B join `near` and list each other, A talks on slot 3, B places A hard left, hard right, centred at gain 0.5: B's output per side; skipped on a relay without it), after the idle sleep (five pages, each alone in a room): the mic test, the meter, switching to voice activation, unmuting voice activation after a long self-mute, the side mouse button (trusted CDP events) and the key held across it; voice activation in no room (nothing opened or sent) and after a join; labels hidden until the first open (the saved input and output devices still used); a microphone plugged in later (`devicechange`); the meter across a disconnect; the meter without and with the microphone permission, an encoder that refuses eco or everything, a WebKit-like context that starts only inside a press, relay restart with backoff, mic refused. `MV_ENGINE=../tmp-min/mythos-voice.js` runs it on the minified engine | Playwright Chromium, ffmpeg, the relay binaries: `VOZ_RELAY`, `VOZ_MINT`, `VOZ_BOT`, `VOZ_KEY`, `VOZ_ROOMS` (defaults: `/tmp/qa/voice/bin/*`, `/tmp/qa/voice/voz.key`, the server repo's `voz-rooms.example.json`) |
| `node server.mjs [port]` | the test page by hand: http://127.0.0.1:8291/test/index.html (COOP/COEP like the game page; `/mint` mints tokens with vozmint) | a relay on 7291 |

`make-fixtures.sh` writes `fala.wav` (bursts of a voice-like harmonic tone,
0.7 s every 2 s, for the latency onsets and the voice-activation gate); the
e2e makes it when missing. The Lua side: `luajit
tools/voz-luatest/game_voice_test.lua` (its last test checks that every
`g_voice` call of `engine_full.lua` is bound in `luafunctions.cpp`, and drives
`voice.lua` through a binding-shaped `g_voice`).

Results here (headless Chromium 153, 4 shared CPUs, another agent's browser
using about 3 cores of the same machine), 59 of 59 e2e checks on the final
source engine and on its minified copy (an earlier run this round, before the
last check was added, 58 of 58): 126 frames for
5 s of push-to-talk, one END, output RMS -19 to -20 dBFS, Opus 55-56 B per
40 ms frame averaged over talk and pauses (about 1.5 KB/s up per talker with
the 3-byte header). Mouth-to-ear on loopback: 136-178 ms warm and 157-171 ms
right after the idle sleep (B's 42 ms output latency included); the
reviewer's runs saw 150-180 ms; all under 250 ms. CPU, % of one core: the
page's main thread 1.1-1.3 while talking or listening and 0.2-0.6 idle; the
whole renderer process (all its threads, the audio thread included) 3.9-5.8
while talking or listening and 0.7-1.2 idle; Chromium's audio service 4.7-5.5
while talking and 3.7 idle (the fake microphone keeps capturing while a
stream is open). JS heap under 2 MB; the context asleep when idle; relay
restart: 1012, then 5 attempts with growing backoff, one socket each, online
again.

The near room (stereo mixer, slot 3, `spatial`): 65 of 65 e2e checks with a
relay that has the near room, on the source engine and on its minified copy
(59 of 59 with a relay without it, the near step skipped). B hears A placed
hard left at -20 to -22 dBFS on the left and nothing on the right (-120), hard
right the other way round, centred at gain 0.5 on both sides 5.6-6.8 dB down
(peak); output RMS of a centred voice -19.4 dBFS as before (the left channel
holds the same samples the mono mix had); mouth-to-ear 119-134 ms. CPU against
the engine before this change, back to back on the same machine (`--only
cpu`, three runs each, A talking on slot 0): the page's main thread 1.0-1.1%
before and after, the two renderers 4.0-4.2% and 5.8-6.0% before, 4.0-4.2% and
5.8-6.1% after, the audio service 3.6-3.9% before, 3.7-4.1% after, JS heap
2.1 and 2.0 MB both. `mv-mixer` alone in Node, per 128-sample block (2.67 ms):
one voice 0.95 µs before (mono), 1.0 µs now centred, 1.45 µs placed on slot 3;
four voices 2.6, 2.7 and 3.3 µs: at most about 0.15% of one core.
