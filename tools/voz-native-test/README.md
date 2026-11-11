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
the shared 7191) and a second one on 7394 for the `lim.pl` check, and stops
both. It needs the relay tools of the server repository (`VOZ_RELAY`,
`VOZ_MINT`, `VOZ_BOT`, `VOZ_KEY`; defaults under `/tmp/qa/voice`), `ffmpeg`,
and for the browser step Node with Playwright's Chromium.

| Step | What it checks |
|---|---|
| unit | framing (AUDIO, BUNDLE, malformed), jitter buffer (reorder, gap -> concealment, 3 concealments then silence, 400 ms cap, stall backlog, reset per spurt, u8 seq wrap, late, duplicate, lead, J target), Opus round trip per preset |
| openal | a playback device of our own with `ALC_EXT_thread_local_context`, no global context touched (wave backend) |
| native <-> vozbot, native -> native | every frame, OpenAL output (wave backend) or vozbot's recording against the input: RMS envelope within 2 dB |
| behaviour | voice activation only in a room, a spurt per burst, a slot without a room sends nothing, Opus over `lim.pl` is not sent, mic test with the 10 Hz meter and no relay |
| devices | with no relay (meter only, or the mic test) a microphone plugged in later (`--late-mic`) opens and is listed; an idle voz thread still lists it to `getInputDevices`; a slow open (`--slow-open`) is timed in stats `dev` and logged |
| preset | a preset change while talking (`--preset-at`) keeps the encoder to the end of the spurt and takes effect on the next one |
| loss, jitter, stalls | injected on the inbox side (`--loss`, `--jitter`, `--stall`): concealment, the cap, the backlog trimmed |
| terminate | `terminate()` while talking and receiving |
| release | RSS added by the engine and CPU, from `/proc/self` |
| browser | `browser.mjs`: the browser engine's test page in headless Chromium (fake microphone), both directions |

`voz-native-test` alone (see the comment at the top of `main.cpp`):
`--unit`, `--openal-check`, `--compare ref.wav out.wav`, a session against a
relay (`--url --tok --room` with `--send in.wav` and/or `--recv out.wav`), or
`--local-test`, or `--meter-only`; `--late-mic`, `--slow-open` and
`--preset-at` work in any mode. For the real OpenAL playback set `ALSOFT_DRIVERS=wave` and an
`ALSOFT_CONF` file with `[wave] file=out.wav` (and `channels = mono`,
`frequency = 48000`).
