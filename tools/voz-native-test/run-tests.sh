#!/bin/bash
# Mythos Voz: every test of the native engine harness, in order.
#
#   tools/voz-native-test/run-tests.sh <asan build dir> [<release build dir>] [--no-browser]
#
# Starts its own relay on 127.0.0.1:${VOZ_PORT:-7391} (never the shared
# 7191) and stops it at the end. Paths from the environment, as
# browser/voice/test/e2e.mjs: VOZ_RELAY, VOZ_MINT, VOZ_BOT, VOZ_KEY,
# VOZ_ROOMS; VOZ_WORK (a work directory; default a new temporary one);
# PAGE_PORT (8391). The release build (-DVOZ_SANITIZE=OFF) gives the RSS and
# CPU numbers; ASan's own memory would hide the engine's.
set -u
here=$(cd "$(dirname "$0")" && pwd)
ASAN_DIR=${1:?asan build dir}
REL_DIR=${2:-}
[ "$REL_DIR" = "--no-browser" ] && REL_DIR=""
NO_BROWSER=0
for a in "$@"; do [ "$a" = "--no-browser" ] && NO_BROWSER=1; done
BIN=$ASAN_DIR/voz-native-test
REL=${REL_DIR:+$REL_DIR/voz-native-test}
RELAY=${VOZ_RELAY:-/tmp/qa/voice/bin/mythos-voz}
MINT=${VOZ_MINT:-/tmp/qa/voice/bin/vozmint}
BOT=${VOZ_BOT:-/tmp/qa/voice/bin/vozbot}
KEY=${VOZ_KEY:-/tmp/qa/voice/voz.key}
ROOMS=${VOZ_ROOMS:-$here/../../../brevesotserv/tools/voz/voz-rooms.example.json}
[ -f "$ROOMS" ] || ROOMS=/home/user/brevesotserv/tools/voz/voz-rooms.example.json
PORT=${VOZ_PORT:-7391}
PAGE_PORT=${PAGE_PORT:-8391}
URL=ws://127.0.0.1:$PORT/voz
WORK=${VOZ_WORK:-$(mktemp -d)}
mkdir -p "$WORK"
export ASAN_OPTIONS=${ASAN_OPTIONS:-halt_on_error=1:detect_leaks=1}
export UBSAN_OPTIONS=${UBSAN_OPTIONS:-print_stacktrace=1:halt_on_error=1}
FAIL=0
PASS=0

say() { printf '%s\n' "$*"; }
result() { # name ok detail
    if [ "$2" = 1 ]; then PASS=$((PASS + 1)); say "PASS  $1  $3"; else FAIL=$((FAIL + 1)); say "FAIL  $1  $3"; fi
}
tok() { "$MINT" -key "$KEY" -claims "$1"; }
conf() { # name wav [channels] -> prints the env for OpenAL Soft's wave backend
    printf '[general]\ndrivers = wave\nchannels = %s\nsample-type = int16\nfrequency = 48000\n[wave]\nfile = %s\n' "${3:-mono}" "$2" > "$WORK/$1.conf"
    printf 'ALSOFT_DRIVERS=wave ALSOFT_CONF=%s' "$WORK/$1.conf"
}
summary() { grep '"summary":"session"' "$1" | tail -1; }
# sanitizer reports in a log
sanitized() { ! grep -qE 'ERROR: (Address|Leak)Sanitizer|runtime error:|SUMMARY: (Address|Undefined)' "$1"; }
py() { python3 -I -c "$1"; }

relay_pid=""
cleanup() {
    [ -n "$relay_pid" ] && kill "$relay_pid" 2>/dev/null && wait "$relay_pid" 2>/dev/null
}
trap cleanup EXIT

"$RELAY" -listen '' -local 127.0.0.1:$PORT -secret "$KEY" -rooms "$ROOMS" -origin http://127.0.0.1:$PAGE_PORT \
    -per-ip 200 -ip-rate 1000 -ip-burst 1000 > "$WORK/relay.log" 2>&1 &
relay_pid=$!
for i in $(seq 50); do curl -sf http://127.0.0.1:$PORT/health > /dev/null && break; sleep 0.1; done
say "relay pid $relay_pid on $PORT, work $WORK"
WAV=$WORK/fala.wav
[ -f "$WAV" ] || sh "$here/../../browser/voice/test/make-fixtures.sh" "$WAV" > /dev/null

# 1. unit ---------------------------------------------------------------------
"$BIN" --unit > "$WORK/unit.out" 2>&1
n=$(py "import json,sys
c=f=0
for l in open('$WORK/unit.out'):
    try: j=json.loads(l)
    except Exception: continue
    if 'check' in j:
        c+=1; f+= not j['ok']
        if not j['ok']: print('   failed:', j['check'], j.get('detail',''), file=sys.stderr)
print(c, f)")
set -- $n
result "unit: protocol, jitter buffer, codec" $([ "${2:-1}" = 0 ] && sanitized "$WORK/unit.out" && echo 1 || echo 0) "$1 checks, $2 failed"

# 2. OpenAL Soft: own device, thread-local context ----------------------------
env $(conf check "$WORK/openal-check.wav") "$BIN" --openal-check > "$WORK/openal.out" 2>&1
ok=$?
result "openal: own device + ALC_EXT_thread_local_context, game context untouched" $([ $ok = 0 ] && sanitized "$WORK/openal.out" && echo 1 || echo 0) "$(tail -1 "$WORK/openal.out" | cut -c1-200)"

compare() { # ref out -> "<1|0> <summary>": 1 when every loud window is within 2 dB
    local j
    j=$("$BIN" --compare "$1" "$2" --min-db -35 2>&1 | tail -1)
    printf '%s' "$j" | py "import json,sys
try:
    j=json.loads(sys.stdin.read())
    ok=j.get('compare')=='ok' and j['loudWindows']>=20 and j['maxAbsDb']<=2.0
    print(1 if ok else 0, 'lag %.0f ms, %d loud windows, mean |diff| %.2f dB, max %.2f dB, bias %+.2f dB, %.0f%% within 2 dB' % (j['lagMs'], j['loudWindows'], j['meanAbsDb'], j['maxAbsDb'], j['meanDiffDb'], 100*j['within2dB']))
except Exception as e:
    print(0, 'compare failed', e)"
}

# 3. native -> vozbot ------------------------------------------------------------
"$BOT" -url $URL -key "$KEY" -room p:7:1 -guid 902 -out "$WORK/rec-n2b.opus" -dur 15s listen > "$WORK/bot-n2b.log" 2>&1 &
bp=$!
sleep 1.2
"$BIN" --url $URL --tok "$(tok '{"a":21,"c":301,"i":3001,"n":"Nativo","p":"p:7:1","pl":1,"lv":60,"pub":1}')" --room p:7:1 \
    --send "$WAV" --dur 11 --quiet > "$WORK/n2b.out" 2>&1
hx=$?
wait $bp
ffmpeg -nostdin -loglevel error -y -i "$WORK/rec-n2b.opus" -ac 1 -ar 48000 -sample_fmt s16 "$WORK/rec-n2b.wav"
botf=$(py "import json; print(json.loads(open('$WORK/bot-n2b.log').read().strip().splitlines()[-1])['frames'])")
sent=$(summary "$WORK/n2b.out" | py "import json,sys; print(json.loads(sys.stdin.read())['stats']['up']['f'])")
result "native -> vozbot: frames" $([ $hx = 0 ] && [ "$botf" -ge $((sent - 1)) ] && [ "$sent" -ge 260 ] && sanitized "$WORK/n2b.out" && echo 1 || echo 0) "native sent $sent, vozbot got $botf"
d=$(compare "$WAV" "$WORK/rec-n2b.wav")
result "native -> vozbot: decoded envelope within 2 dB of the input" "${d%% *}" "${d#* }"

# 4. vozbot -> native (real OpenAL playback, wave backend) -------------------------
env $(conf b2n "$WORK/out-b2n.wav") "$BIN" --url $URL --tok "$(tok '{"a":22,"c":302,"i":3002,"n":"Ouvinte","p":"p:7:2","lv":60,"pub":1}')" \
    --room p:7:2 --recv "$WORK/out-b2n.wav" --dur 14 --quiet > "$WORK/b2n.out" 2>&1 &
hp=$!
sleep 1.2
"$BOT" -url $URL -key "$KEY" -room p:7:2 -guid 903 -in "$WAV" talk > "$WORK/bot-b2n.log" 2>&1
wait $hp
hx=$?
s=$(summary "$WORK/b2n.out")
r=$(echo "$s" | py "import json,sys; s=json.loads(sys.stdin.read())['stats']; d=s['down']; m=s['mix']; print(d['f'], m['played'], m['conceal'], m['underruns'], d['decErr'])")
set -- $r
result "vozbot -> native: frames played" $([ $hx = 0 ] && [ "$1" -ge 250 ] && [ "$2" -ge $(($1 - 1)) ] && [ "$3" = 0 ] && [ "$4" = 0 ] && [ "$5" = 0 ] && sanitized "$WORK/b2n.out" && echo 1 || echo 0) "got $1, played $2, conceal $3, underruns $4, decErr $5"
d=$(compare "$WAV" "$WORK/out-b2n.wav")
result "vozbot -> native: OpenAL output envelope within 2 dB of the input" "${d%% *}" "${d#* }"

# 5. native -> native (OpenAL on the listener) ----------------------------------
native_pair() { # name room extra-recv-args... ; listener records out-<name>.wav
    local name=$1 room=$2
    shift 2
    env $(conf $name "$WORK/out-$name.wav") "$BIN" --url $URL --tok "$(tok '{"a":24,"c":304,"i":3004,"n":"B'$name'","p":"'$room'","lv":60,"pub":1}')" \
        --room $room --recv "$WORK/out-$name.wav" --dur 15 --quiet "$@" > "$WORK/$name-recv.out" 2>&1 &
    local lp=$!
    sleep 1.2
    "$BIN" --url $URL --tok "$(tok '{"a":23,"c":303,"i":3003,"n":"A'$name'","p":"'$room'","pl":1,"lv":60,"pub":1}')" --room $room \
        --send "$WAV" --dur 11 --quiet > "$WORK/$name-send.out" 2>&1
    SEND_EXIT=$?
    wait $lp
    RECV_EXIT=$?
}
native_pair n2n p:7:3
r=$(summary "$WORK/n2n-recv.out" | py "import json,sys; s=json.loads(sys.stdin.read())['stats']; d=s['down']; m=s['mix']; print(d['f'], m['played'], m['conceal'], m['underruns'], m['maxBuffered'])")
set -- $r
sent=$(summary "$WORK/n2n-send.out" | py "import json,sys; print(json.loads(sys.stdin.read())['stats']['up']['f'])")
result "native -> native: frames" $([ $SEND_EXIT = 0 ] && [ $RECV_EXIT = 0 ] && [ "$1" = "$sent" ] && [ "$3" = 0 ] && [ "$4" = 0 ] && sanitized "$WORK/n2n-recv.out" && sanitized "$WORK/n2n-send.out" && echo 1 || echo 0) "sent $sent, got $1, played $2, conceal $3, underruns $4, max buffered $5 ms"
d=$(compare "$WAV" "$WORK/out-n2n.wav")
result "native -> native: OpenAL output envelope within 2 dB of the input" "${d%% *}" "${d#* }"

# 5b. behaviour the browser engine has (voiceengine.h) ------------------------------
# voice activation in no room: nothing is captured or sent, no 'talk'
"$BIN" --url $URL --tok "$(tok '{"a":31,"c":311,"i":3011,"n":"VadNoRoom","p":"p:7:8","pl":1,"lv":60,"pub":1}')" --room '' \
    --send "$WAV" --vad --vad-db -40 --dur 5 --quiet > "$WORK/vad-noroom.out" 2>&1
r=$(summary "$WORK/vad-noroom.out" | py "import json,sys; j=json.loads(sys.stdin.read()); print(j['events'].get('talk',0), j['micOpens'], j['stats']['up']['f'], j['stats']['mic'])")
set -- $r
result "voice activation in no room: microphone closed, nothing sent" $([ "$1" = 0 ] && [ "$2" = 0 ] && [ "$3" = 0 ] && sanitized "$WORK/vad-noroom.out" && echo 1 || echo 0) "talk events $1, mic opens $2, frames $3, mic $4"
# voice activation in a room: one spurt per burst of the fixture (0.7 s every 2 s)
"$BIN" --url $URL --tok "$(tok '{"a":32,"c":312,"i":3012,"n":"VadL","p":"p:7:9","lv":60,"pub":1}')" --room p:7:9 \
    --recv "$WORK/out-vad.wav" --wav-out --dur 14 --quiet > "$WORK/vad-recv.out" 2>&1 &
lp=$!
sleep 1.2
"$BIN" --url $URL --tok "$(tok '{"a":33,"c":313,"i":3013,"n":"VadT","p":"p:7:9","pl":1,"lv":60,"pub":1}')" --room p:7:9 \
    --send "$WAV" --vad --vad-db -40 --dur 10.5 --quiet > "$WORK/vad-send.out" 2>&1
wait $lp
r=$(summary "$WORK/vad-send.out" | py "import json,sys; j=json.loads(sys.stdin.read()); print(j['events'].get('talk',0), j['stats']['up']['f'], j['micOpens'])")
set -- $r
r2=$(summary "$WORK/vad-recv.out" | py "import json,sys; j=json.loads(sys.stdin.read()); s=j['stats']; print(s['down']['end'], s['down']['f'], j['events'].get('spk',0))")
set -- $r $r2
result "voice activation in a room: a spurt per burst, silence sends nothing" $([ "$1" -ge 8 ] && [ "$1" -le 12 ] && [ "$2" -ge 60 ] && [ "$2" -le 200 ] && [ "$4" -ge 4 ] && [ "$4" -le 6 ] && [ "$5" = "$2" ] && sanitized "$WORK/vad-send.out" && echo 1 || echo 0) "talk edges $1 (on+off), frames sent $2 (260 = always open), END frames heard $4, frames heard $5, spk edges $6, mic opens $3"
# push-to-talk on a slot without a room (guild, only in a party): the gate
# opens but no frame goes out
"$BIN" --url $URL --tok "$(tok '{"a":34,"c":314,"i":3014,"n":"NoRoom","p":"p:7:10","pl":1,"lv":60,"pub":1}')" --room p:7:10 \
    --send "$WAV" --slot 1 --dur 3 --quiet > "$WORK/noroom.out" 2>&1
r=$(summary "$WORK/noroom.out" | py "import json,sys; j=json.loads(sys.stdin.read()); u=j['stats']['up']; print(u['f'], u['noRoom'], j['events'].get('talk',0))")
set -- $r
result "a slot with no room: frames not sent" $([ "$1" = 0 ] && [ "$2" -ge 60 ] && sanitized "$WORK/noroom.out" && echo 1 || echo 0) "sent $1, held back $2 (noRoom), talk edges $3"
# the welcome's lim.pl: Opus over it is never sent (a relay with maxPayload 60)
py "import json; r=json.load(open('$ROOMS')); r['maxPayload']=60; json.dump(r, open('$WORK/rooms-pl60.json','w'))"
"$RELAY" -listen '' -local 127.0.0.1:$((PORT + 3)) -secret "$KEY" -rooms "$WORK/rooms-pl60.json" > "$WORK/relay-pl60.log" 2>&1 &
rp=$!
for i in $(seq 50); do curl -sf http://127.0.0.1:$((PORT + 3))/health > /dev/null && break; sleep 0.1; done
"$BIN" --url ws://127.0.0.1:$((PORT + 3))/voz --tok "$(tok '{"a":35,"c":315,"i":3015,"n":"Pl","p":"p:7:11","pl":1,"lv":60,"pub":1}')" --room p:7:11 \
    --send "$WAV" --dur 4 --quiet > "$WORK/pl60.out" 2>&1
bad=$(curl -s http://127.0.0.1:$((PORT + 3))/stats | py "import json,sys; j=json.load(sys.stdin); print(j['drops']['bad'], j['in_msgs'])")
kill $rp 2>/dev/null; wait $rp 2>/dev/null
r=$(summary "$WORK/pl60.out" | py "import json,sys; j=json.loads(sys.stdin.read()); u=j['stats']['up']; print(u['max'], u['big'], u['f'])")
set -- $r $bad
result "lim.pl 60 from the welcome: bigger Opus frames are not sent" $([ "$1" = 60 ] && [ "$2" -ge 1 ] && [ "$4" = 0 ] && sanitized "$WORK/pl60.out" && echo 1 || echo 0) "limit $1 B, held back $2, sent $3; relay bad drops $4 (audio + control messages in: $5)"

# 5d. the global push-to-talk key (GetAsyncKeyState on Windows; simulated here) ------
# the game's key held 1-4 s and the background key 2-6 s: held apart, one spurt
"$BIN" --url $URL --tok "$(tok '{"a":36,"c":316,"i":3016,"n":"GkL","p":"p:7:12","lv":60,"pub":1}')" --room p:7:12 \
    --recv "$WORK/out-gk.wav" --wav-out --dur 11 --quiet > "$WORK/gk-recv.out" 2>&1 &
lp=$!
sleep 1.2
"$BIN" --url $URL --tok "$(tok '{"a":37,"c":317,"i":3017,"n":"GkT","p":"p:7:12","pl":1,"lv":60,"pub":1}')" --room p:7:12 \
    --send "$WAV" --loop --ptt-window 1,4 --global-key 2,6 --dur 8 --quiet > "$WORK/gk-send.out" 2>&1
wait $lp
r=$(summary "$WORK/gk-send.out" | py "import json,sys; j=json.loads(sys.stdin.read()); print(j['talkEdges'], j['stats']['up']['f'])")
r2=$(summary "$WORK/gk-recv.out" | py "import json,sys; d=json.loads(sys.stdin.read())['stats']['down']; print(d['f'], d['end'])")
set -- $r $r2
result "game key 1-4 s + background key 2-6 s: held apart, one spurt" $([ "$1" = 2 ] && [ "$2" -ge 120 ] && [ "$2" -le 130 ] && [ "$3" = "$2" ] && [ "$4" = 1 ] && sanitized "$WORK/gk-send.out" && echo 1 || echo 0) "talk edges $1, sent $2, heard $3, END $4"
# the background key with no party room: ignored until released
"$BIN" --url $URL --tok "$(tok '{"a":38,"c":318,"i":3018,"n":"GkN","p":"p:7:13","pl":1,"lv":60,"pub":1}')" --room '' \
    --send "$WAV" --global-key 0.5,3 --dur 4 --quiet > "$WORK/gk-none.out" 2>&1
r=$(summary "$WORK/gk-none.out" | py "import json,sys; j=json.loads(sys.stdin.read()); print(j['talkEdges'], j['stats']['up']['f'], j['micOpens'])")
set -- $r
result "background key with no room: ignored (no gate, microphone closed)" $([ "$1" = 0 ] && [ "$2" = 0 ] && [ "$3" = 0 ] && sanitized "$WORK/gk-none.out" && echo 1 || echo 0) "talk edges $1, sent $2, mic opens $3"

# 5c. "Testar microfone" and the level meter: no connection at all ------------------
env $(conf lt "$WORK/out-localtest.wav") "$BIN" --local-test --send "$WAV" --recv "$WORK/out-localtest.wav" --meter --dur 10.5 --quiet > "$WORK/localtest.out" 2>&1
hx=$?
r=$(summary "$WORK/localtest.out" | py "import json,sys; j=json.loads(sys.stdin.read()); s=j['stats']; print(s['up']['f'], s['up']['enc'], s['mix']['played'], j['events'].get('level',0), s['state'])")
set -- $r
d=$(compare "$WAV" "$WORK/out-localtest.wav")
result "mic test (local loopback through Opus and OpenAL) and 10 Hz meter, no relay" $([ $hx = 0 ] && [ "$1" = 0 ] && [ "$3" -ge $(($2 - 3)) ] && [ "$4" -ge 95 ] && [ "$4" -le 110 ] && [ "${d%% *}" = 1 ] && sanitized "$WORK/localtest.out" && echo 1 || echo 0) "sent $1, encoded $2, played $3, level events $4, state $5; ${d#* }"

# 5e. a microphone plugged in later, with no relay (the settings window's meter, the
# mic test): tried again and the device lists refreshed, so it opens within ~3 s
"$BIN" --meter-only --late-mic 1.5 --dur 7 --quiet > "$WORK/late-meter.out" 2>&1
r=$(summary "$WORK/late-meter.out" | py "import json,sys; j=json.loads(sys.stdin.read()); print(j['micOkAtMs'], j['devicesAtMs'], j['events'].get('level',0), ','.join(j['inputsAtEnd']) or '-', j['micTries'])")
set -- $r
result "meter only, no relay: a microphone plugged in at 1.5 s opens and is listed" $([ "$1" -ge 1500 ] && [ "$1" -le 4600 ] && [ "$2" -ge 1500 ] && [ "$2" -le "$1" ] && [ "$3" -ge 15 ] && [ "$4" = Headset ] && sanitized "$WORK/late-meter.out" && echo 1 || echo 0) "mic ok at $1 ms, 'devices' with it at $2 ms, level events $3, getInputDevices: $4, open tries $5"
"$BIN" --local-test --late-mic 1.5 --dur 7 --quiet > "$WORK/late-test.out" 2>&1
r=$(summary "$WORK/late-test.out" | py "import json,sys; j=json.loads(sys.stdin.read()); print(j['micOkAtMs'], j['devicesAtMs'], j['stats']['mix']['played'], j['micTries'])")
set -- $r
result "mic test, no relay: a microphone plugged in at 1.5 s opens and plays back" $([ "$1" -ge 1500 ] && [ "$1" -le 4600 ] && [ "$2" -ge 1500 ] && [ "$3" -ge 30 ] && sanitized "$WORK/late-test.out" && echo 1 || echo 0) "mic ok at $1 ms, 'devices' with it at $2 ms, frames played $3, open tries $4"
# the voz thread idle (the meter closed at 1 s), a microphone at 2 s: getInputDevices
# from the game's thread still lists it (the voz thread's copy is old, so it lists anew)
"$BIN" --meter-only --late-mic 2 --meter-off-at 1 --dur 8 --quiet > "$WORK/late-idle.out" 2>&1
r=$(summary "$WORK/late-idle.out" | py "import json,sys; j=json.loads(sys.stdin.read()); print(','.join(j['inputsAtEnd']) or '-', j['micOpens'])")
set -- $r
result "idle voz thread: getInputDevices lists a microphone plugged in later" $([ "$1" = Headset ] && [ "$2" = 0 ] && sanitized "$WORK/late-idle.out" && echo 1 || echo 0) "getInputDevices: $1, mic opens $2"

# a device call that blocks the voz thread is timed: stats dev.* and one log line
"$BIN" --meter-only --send "$WAV" --slow-open 150 --dur 3 > "$WORK/slow-open.out" 2>&1
r=$(summary "$WORK/slow-open.out" | py "import json,sys; d=json.loads(sys.stdin.read())['stats']['dev']; print(d['micOpenMax'], d['slow'], d['listMax'])")
logged=$(grep -c 'opening the microphone took' "$WORK/slow-open.out")
set -- $r
result "a slow microphone open is timed (stats dev, log)" $([ "$1" -ge 150 ] && [ "$2" -ge 1 ] && [ "$logged" = 1 ] && sanitized "$WORK/slow-open.out" && echo 1 || echo 0) "micOpenMax $1 ms, slow calls $2, listMax $3 ms, log lines $logged"

# 5f. a preset change while talking takes effect with the next spurt (the browser's rule:
# a new encoder in the middle of a spurt breaks the codec state the listeners decode)
"$BIN" --url $URL --tok "$(tok '{"a":39,"c":319,"i":3019,"n":"PrL","p":"p:7:14","lv":60,"pub":1}')" --room p:7:14 \
    --recv "$WORK/out-preset.wav" --wav-out --dur 13 --quiet > "$WORK/preset-recv.out" 2>&1 &
lp=$!
sleep 1.2
"$BIN" --url $URL --tok "$(tok '{"a":40,"c":320,"i":3020,"n":"PrT","p":"p:7:14","pl":1,"lv":60,"pub":1}')" --room p:7:14 \
    --send "$WAV" --loop --ptt-window 0.5,5 --global-key 6,9 --preset-at 2.5,2 --dur 10.5 --quiet > "$WORK/preset-send.out" 2>&1
wait $lp
r=$(summary "$WORK/preset-send.out" | py "import json,sys
j=json.loads(sys.stdin.read()); tl=j['timeline']
mid=[e[3] for e in tl if 3000<=e[0]<=5000]
def rate(a,b):
    x=[e for e in tl if a<=e[0]<=b]
    return (x[-1][2]-x[0][2])/max(1,x[-1][1]-x[0][1]) if len(x)>=2 else 0
print(max(mid) if mid else -1, tl[-1][3] if tl else -1, round(rate(1500,5000)), round(rate(7000,9200)), j['talkEdges'], j['stats']['up']['f'])")
r2=$(summary "$WORK/preset-recv.out" | py "import json,sys; d=json.loads(sys.stdin.read())['stats']['down']; print(d['f'], d['decErr'], d['end'])")
set -- $r $r2
result "preset change while talking: same encoder to the end of the spurt, new one on the next" $([ "$1" = 1 ] && [ "$2" = 2 ] && [ "$4" -gt $(($3 + 20)) ] && [ "$5" = 4 ] && [ "$7" = "$6" ] && [ "$8" = 0 ] && [ "$9" = 2 ] && sanitized "$WORK/preset-send.out" && echo 1 || echo 0) "encoders made by 3-5 s: $1, at the end: $2; bytes/frame first spurt $3, second $4; talk edges $5; sent $6, heard $7, decErr $8, END $9"

# 5g. the near room (slot 3) through the real OpenAL output, stereo: a stand-in relay
# on PORT+4 sends tone spurts on slots 0 and 3 while the harness gives the speaker
# places (setUserSpatial); the relay of this run may not have the near room yet
env $(conf near "$WORK/out-near.wav" stereo) "$BIN" --spatial-test --out "$WORK/out-near.wav" --port $((PORT + 4)) --quiet > "$WORK/near.out" 2>&1
hx=$?
n=$(py "import json,sys
c=f=0
for l in open('$WORK/near.out'):
    try: j=json.loads(l)
    except Exception: continue
    if 'check' in j:
        c+=1; f+= not j['ok']
        print('      %s %s  %s' % ('ok  ' if j['ok'] else 'FAIL', j['check'], j.get('detail','')), file=sys.stderr)
print(c, f)" 2>"$WORK/near.checks")
cat "$WORK/near.checks"
set -- $n
result "near (slot 3): pan -1/0/+1, gain, slot 0 untouched, 50 ms ramp, slot change heard with its frames" $([ $hx = 0 ] && [ "${1:-0}" -ge 9 ] && [ "${2:-1}" = 0 ] && sanitized "$WORK/near.out" && echo 1 || echo 0) "$1 checks, $2 failed (stereo OpenAL output, wave backend)"

# 5h. the near room through the relay, when it has it (the welcome's "near"): native
# -> native on slot 3, each listing the other's creature; the listener places the
# speaker hard left (stereo OpenAL output); a bystander lists the speaker, who
# does not list it back: it hears nothing
env $(conf nearrelay "$WORK/out-nearrelay.wav" stereo) "$BIN" --url $URL --tok "$(tok '{"a":41,"c":321,"i":3021,"n":"PertoL","lv":60}')" \
    --room near --near-cids 3022 --place 1,-1 --recv "$WORK/out-nearrelay.wav" --dur 10 --quiet > "$WORK/nearrelay-recv.out" 2>&1 &
lp=$!
"$BIN" --url $URL --tok "$(tok '{"a":43,"c":323,"i":3023,"n":"PertoX","lv":60}')" --room near --near-cids 3022 \
    --recv "$WORK/out-nearrelay-x.wav" --wav-out --dur 10 --quiet > "$WORK/nearrelay-x.out" 2>&1 &
xp=$!
sleep 1.2
"$BIN" --url $URL --tok "$(tok '{"a":42,"c":322,"i":3022,"n":"PertoT","lv":60}')" --room near --near-cids 3021 --slot 3 \
    --send "$WAV" --dur 7 --quiet > "$WORK/nearrelay-send.out" 2>&1
SEND_EXIT=$?
wait $lp
RECV_EXIT=$?
wait $xp
xf=$(summary "$WORK/nearrelay-x.out" | py "import json,sys; print(json.loads(sys.stdin.read())['stats']['down']['f'])")
r=$(summary "$WORK/nearrelay-recv.out" | py "import json,sys,wave,array,math
j=json.loads(sys.stdin.read())
if not j['nearOffered']:
    print('skip'); sys.exit()
s=j['stats']; d=s['down']; m=s['mix']
L=R=n=0.0
try:
    w=wave.open('$WORK/out-nearrelay.wav'); a=array.array('h', w.readframes(w.getnframes())); ch=w.getnchannels()
    l=a[0::2]; r=a[1::2]
    for i in range(0, len(l)-4800, 4800):
        pl=sum(x*x for x in l[i:i+4800])/4800.0; pr=sum(x*x for x in r[i:i+4800])/4800.0
        if (pl+pr)/2 > (32768*0.01)**2: L+=pl; R+=pr; n+=1
except Exception as e:
    ch=0
db=lambda p: 10*math.log10(p/n/32768/32768+1e-12) if n else -120
print(1 if ch==2 and d['f']>=100 and m['played']>=d['f']-2 and n>=10 and db(L)-db(R)>20 and j['nearIn']>=1 and j['placedSid']>0 and '$xf'=='0' else 0,
      'in near %d, got %d, played %d, decErr %d; %d loud windows: left %.1f dB, right %.1f dB; the bystander not listed back got $xf frames' % (j['nearIn'], d['f'], m['played'], d['decErr'], n, db(L), db(R)))")
if [ "$r" = skip ]; then
    say "SKIP  near through the relay: this relay has no near room (welcome without \"near\")"
else
    result "near through the relay: slot 3 heard only near, placed on the left (stereo OpenAL)" $([ $SEND_EXIT = 0 ] && [ $RECV_EXIT = 0 ] && [ "${r%% *}" = 1 ] && sanitized "$WORK/nearrelay-recv.out" && sanitized "$WORK/nearrelay-send.out" && echo 1 || echo 0) "${r#* }"
fi

# 6. injected loss and jitter (listener side) ---------------------------------------
native_pair loss p:7:4 --loss 0.05 --jitter 60 --seed 7
r=$(summary "$WORK/loss-recv.out" | py "import json,sys; s=json.loads(sys.stdin.read())['stats']; m=s['mix']; i=s['inject']; print(i['lost'], i['delayed'], m['played'], m['conceal'], m['late'], m['maxBuffered'], max(m['targets'].values()) if m['targets'] else 0, m['underruns'])")
set -- $r
result "loss 5% + jitter 0-60 ms: concealment covers the gaps, target grows" $([ $RECV_EXIT = 0 ] && [ "$4" -ge 1 ] && [ "$6" -le 400 ] && [ "$2" -ge 200 ] && sanitized "$WORK/loss-recv.out" && echo 1 || echo 0) "lost $1, delayed $2, played $3, concealed $4, late $5, max buffered $6 ms, target $7 ms, underruns $8"
d=$(compare "$WAV" "$WORK/out-loss.wav")
say "      loss/jitter output envelope (not held to 2 dB): ${d#* }"

# 7. stalls (TCP-like: everything held 700 ms every 3 s, then flushed) ---------------
native_pair stall p:7:5 --stall 700 --stall-every 3000
r=$(summary "$WORK/stall-recv.out" | py "import json,sys; s=json.loads(sys.stdin.read())['stats']; m=s['mix']; i=s['inject']; print(i['stalled'], m['played'], m['trimmed'], m['conceal'], m['maxBuffered'], m['resets'])")
set -- $r
result "stall 700 ms / 3 s: backlog trimmed, buffer never over 400 ms" $([ $RECV_EXIT = 0 ] && [ "$3" -ge 1 ] && [ "$5" -le 400 ] && sanitized "$WORK/stall-recv.out" && echo 1 || echo 0) "stalled frames $1, played $2, trimmed $3, concealed $4, max buffered $5 ms, resets $6"

# 8. terminate while talking and receiving ------------------------------------------
env $(conf term "$WORK/out-term.wav") "$BIN" --url $URL --tok "$(tok '{"a":25,"c":305,"i":3005,"n":"Term","p":"p:7:6","pl":1,"lv":60,"pub":1}')" --room p:7:6 \
    --send "$WAV" --loop --recv "$WORK/out-term.wav" --dur 30 --terminate-at 5 --quiet > "$WORK/term-a.out" 2>&1 &
ap=$!
sleep 0.8
"$BIN" --url $URL --tok "$(tok '{"a":26,"c":306,"i":3006,"n":"Peer","p":"p:7:6","lv":60,"pub":1}')" --room p:7:6 \
    --send "$WAV" --loop --dur 7 --quiet > "$WORK/term-b.out" 2>&1 &
bp=$!
( sleep 20; kill -9 $ap 2>/dev/null ) &
wd=$!
wait $ap
ax=$?
kill $wd 2>/dev/null
wait $bp
r=$(summary "$WORK/term-a.out" | py "import json,sys; j=json.loads(sys.stdin.read()); s=j['stats']; print(j['terminateMs'], j['terminatedEarly'], s.get('up',{}).get('f',0) if s else -1, s.get('down',{}).get('f',0) if s else -1)")
set -- $r
result "terminate() while talking and receiving: returns, no crash, no sanitizer report" $([ $ax = 0 ] && [ "$2" = True ] && sanitized "$WORK/term-a.out" && echo 1 || echo 0) "terminate took $1 ms (exit $ax), had sent $3 and received $4 frames"

# 9. RSS and CPU (release build, /proc/self) ------------------------------------------
if [ -n "$REL" ]; then
    rel_run() { # name args...
        local name=$1
        shift
        "$REL" --url $URL "$@" --dur 20 --quiet --stats-out "$WORK/$name.json" > "$WORK/$name.out" 2>&1
    }
    # listening: a peer talks for 20 s
    env $(conf rl "$WORK/out-rl.wav") "$REL" --url $URL --tok "$(tok '{"a":27,"c":307,"i":3007,"n":"RelL","p":"p:7:7","lv":60,"pub":1}')" --room p:7:7 \
        --recv "$WORK/out-rl.wav" --dur 22 --quiet --stats-out "$WORK/rel-listen.json" > "$WORK/rel-listen.out" 2>&1 &
    lp=$!
    sleep 1.2
    rel_run rel-talk --tok "$(tok '{"a":28,"c":308,"i":3008,"n":"RelT","p":"p:7:7","pl":1,"lv":60,"pub":1}')" --room p:7:7 --send "$WAV" --loop
    wait $lp
    for n in rel-talk rel-listen; do
        r=$(py "import json; j=json.load(open('$WORK/$n.json')); p=j['proc']; print('RSS before the engine %d KB, at join %d KB, end %d KB (+%.1f MB), max %d KB; CPU %.2f%% of one core; threads %d' % (j['rssKbBefore'], j['rssKbAtJoin'], j['rssKb'], (j['rssKb']-j['rssKbBefore'])/1024, max(x['rssKb'] for x in p), j['cpuPctOfCore'], j['threads']))")
        say "      $n: $r"
    done
    ok=$(py "import json; a=json.load(open('$WORK/rel-talk.json')); b=json.load(open('$WORK/rel-listen.json')); print(1 if (a['rssKb']-a['rssKbBefore'])<=5*1024 and (b['rssKb']-b['rssKbBefore'])<=5*1024 and a['cpuPctOfCore']<=5 and b['cpuPctOfCore']<=5 else 0)")
    result "release: RSS added by the engine <= 5 MB, CPU <= 5% of a core (talking / listening)" "$ok" "see the two lines above"
    # listening to a near speaker with a place (stereo OpenAL) against the same frames
    # on slot 0 with no place: the place adds no measurable work
    for v in near plain; do
        env $(conf rel-$v "$WORK/out-rel-$v.wav" stereo) "$REL" --spatial-test --out "$WORK/out-rel-$v.wav" --port $((PORT + 4)) --quiet $([ $v = plain ] && echo --plain) > "$WORK/rel-$v.out" 2>&1
    done
    r=$(py "import json
bad=0
def s(n):
    global bad
    out=None
    for l in open('$WORK/rel-%s.out' % n):
        try: j=json.loads(l)
        except Exception: continue
        if 'check' in j and not j['ok']: bad+=1
        if j.get('summary')=='spatial': out=j
    return out
a=s('near'); b=s('plain')
print(1 if a and b and not bad and a['cpuPctOfCore']<=5 and a['cpuPctOfCore']<=b['cpuPctOfCore']+0.5 else 0, 'near with places %.2f%%, the same frames on slot 0 %.2f%% of one core; RSS +%.1f / +%.1f MB; failed checks %d' % (a['cpuPctOfCore'], b['cpuPctOfCore'], (a['rssKb']-a['rssKbBefore'])/1024, (b['rssKb']-b['rssKbBefore'])/1024, bad) if a and b else 'no summary')")
    result "release: listening on slot 3 with places costs what slot 0 does" "${r%% *}" "${r#* }"
fi

# 10. the browser engine ------------------------------------------------------------
if [ $NO_BROWSER = 0 ]; then
    VOZ_URL=$URL PAGE_PORT=$PAGE_PORT node "$here/browser.mjs" --bin "$BIN" --wav "$WAV" --work "$WORK" > "$WORK/browser.out" 2>&1
    bx=$?
    grep '"check"' "$WORK/browser.out" | py "import json,sys
for l in sys.stdin:
    j=json.loads(l); print(('      ok   ' if j['ok'] else '      FAIL ')+j['check']+'  '+str(j.get('detail',''))[:160])"
    result "browser engine <-> native engine (Playwright, headless Chromium, fake mic)" $([ $bx = 0 ] && echo 1 || echo 0) "$(tail -1 "$WORK/browser.out")"
fi

# relay side
curl -s http://127.0.0.1:$PORT/stats | py "import json,sys; j=json.load(sys.stdin); print('      relay: in_msgs %d, out_frames %d, drops %s, closes %s' % (j['in_msgs'], j['out_frames'], j['drops'], j['closes']))"
say "$PASS passed, $FAIL failed (logs in $WORK)"
[ $FAIL = 0 ]
