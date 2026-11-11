# voz-native-test: the native voice engine on Linux

Builds the native engine's own files (`src/framework/voice`: codec, jitter
buffer, OpenAL capture and playback, `NativeVoiceEngine`) with
`-DVOICE_STANDALONE`, so nothing of the framework comes in, against the
system's libopus and OpenAL Soft (`pkg-config opus openal`) and ixwebsocket
v12.0.0 (the client's vcpkg baseline) with TLS through OpenSSL. The default
build adds `-fsanitize=address,undefined`.

```sh
# a local IXWebSocket clone is optional (else CMake clones v12.0.0)
git clone --depth 1 --branch v12.0.0 https://github.com/machinezone/IXWebSocket /tmp/ixws
cmake -S tools/voz-native-test -B /tmp/voz-asan -G Ninja -DIXWEBSOCKET_SOURCE_DIR=/tmp/ixws
cmake -S tools/voz-native-test -B /tmp/voz-rel -G Ninja -DIXWEBSOCKET_SOURCE_DIR=/tmp/ixws \
      -DVOZ_SANITIZE=OFF -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/voz-asan && cmake --build /tmp/voz-rel
tools/voz-native-test/run-tests.sh /tmp/voz-asan /tmp/voz-rel
```

`run-tests.sh` starts its own relay on 127.0.0.1:7391 (`VOZ_PORT`; never
the shared 7191), a second one on 7394 for the `lim.pl` check and the near
step's stand-in relay on 7395 (`VOZ_PORT` + 3 and + 4), and stops them all. It needs the relay tools of the server repository (`VOZ_RELAY`,
`VOZ_MINT`, `VOZ_BOT`, `VOZ_KEY`; defaults under `/tmp/qa/voice`), `ffmpeg`,
and for the browser step Node with Playwright's Chromium.

| Step | What it checks |
|---|---|
| unit | framing (AUDIO, BUNDLE, malformed, slot 3 up and down), jitter buffer (reorder, gap -> concealment, 3 concealments then silence, 400 ms cap, stall backlog, reset per spurt, u8 seq wrap, late, duplicate, lead, J target, each frame's slot), Opus round trip per preset |
| openal | a playback device of our own with `ALC_EXT_thread_local_context`, no global context touched (wave backend) |
| native <-> vozbot, native -> native | every frame, OpenAL output (wave backend) or vozbot's recording against the input: RMS envelope within 2 dB |
| behaviour | voice activation only in a room, a spurt per burst, a slot without a room sends nothing, Opus over `lim.pl` is not sent, mic test with the 10 Hz meter and no relay |
| devices | with no relay (meter only, or the mic test) a microphone plugged in later (`--late-mic`) opens and is listed; an idle voz thread still lists it to `getInputDevices`; a slow open (`--slow-open`) is timed in stats `dev` and logged |
| preset | a preset change while talking (`--preset-at`) keeps the encoder to the end of the spurt and takes effect on the next one |
| near (slot 3) | `--spatial-test`: a stand-in relay in the harness (the run's relay may not have the near room) sends tone spurts from one speaker on slots 0 and 3 while the harness calls `setUserSpatial`; the real OpenAL playback to a stereo WAV (wave backend): slot 3 with no place as slot 0, pan -1 and +1 on one side only (over 40 dB apart), pan 0 at gain 0.5 centred 6 dB down, slot 0 centred while a place is set, a new place while talking in about 50 ms with no click, a slot change inside a spurt heard when its frames play (within 60 ms of the sound itself) |
| near through the relay | only with a relay that has the near room (the welcome's `near`; else `SKIP`): native -> native on slot 3, each listing the other's creature (`--room near --near-cids`), the listener placing the speaker hard left (`--place 1,-1`, stereo OpenAL); a bystander the speaker does not list back hears nothing |
| loss, jitter, stalls | injected on the inbox side (`--loss`, `--jitter`, `--stall`): concealment, the cap, the backlog trimmed |
| terminate | `terminate()` while talking and receiving |
| release | RSS added by the engine and CPU, from `/proc/self`; listening to a near speaker with places against the same frames on slot 0 (`--spatial-test`, `--plain`) |
| browser | `browser.mjs`: the browser engine's test page in headless Chromium (fake microphone), both directions |

`voz-native-test` alone (see the comment at the top of `main.cpp`):
`--unit`, `--openal-check`, `--compare ref.wav out.wav`, a session against a
relay (`--url --tok --room` with `--send in.wav` and/or `--recv out.wav`), or
`--local-test`, or `--meter-only`, or `--spatial-test --out out.wav [--port
7395] [--plain]`; `--late-mic`, `--slow-open` and
`--preset-at` work in any mode. For the real OpenAL playback set `ALSOFT_DRIVERS=wave` and an
`ALSOFT_CONF` file with `[wave] file=out.wav` (and `channels = mono`,
`frequency = 48000`; `channels = stereo` for `--spatial-test`).

How OpenAL Soft (1.23, stereo output, no HRTF) pans a near speaker placed at
x = pan, z = -sqrt(1 - pan^2): at pan 0 exactly as a source at the listener
(every other voice: -4.5 dB per side); the near side within 0.5 dB of a
constant-power law, the far side faster (-13 dB at pan 0.5, gone from 0.87);
the total power 1.5 dB over the centre's at pan ±1. With HRTF (headphones on
Windows, `hrtf = auto`) or a surround output, OpenAL places it the same way
for that output.
