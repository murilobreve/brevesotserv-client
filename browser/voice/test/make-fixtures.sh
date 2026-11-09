#!/bin/sh
# Test fixture for the voice e2e test: fala.wav, 10 s at 48 kHz mono 16-bit,
# looped by Chrome's fake microphone (--use-file-for-fake-audio-capture).
# Every 2 s a 0.7 s "syllable train" (a 180 Hz voice-like harmonic stack,
# amplitude-modulated at 5 Hz) starts abruptly: the onset is what the latency
# probe times; the 1.3 s of near silence between bursts closes the
# voice-activation gate.
set -e
cd "$(dirname "$0")"
out=${1:-fala.wav}
expr='if(lt(mod(t,2),0.7),0.45*(0.5*sin(2*PI*180*t)+0.3*sin(2*PI*360*t)+0.2*sin(2*PI*540*t)+0.12*sin(2*PI*900*t)+0.08*sin(2*PI*1500*t))*(0.65+0.35*sin(2*PI*5*t)),0.0004*(random(0)-0.5))'
if command -v ffmpeg >/dev/null 2>&1; then
  ffmpeg -nostdin -loglevel error -y -f lavfi -i "aevalsrc=exprs='$expr':s=48000:d=10" -ac 1 -ar 48000 -sample_fmt s16 "$out"
else
  python3 - "$out" <<'PY'
import math, random, struct, sys, wave
w = wave.open(sys.argv[1], 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(48000)
frames = bytearray()
for i in range(480000):
    t = i / 48000.0
    if (t % 2.0) < 0.7:
        v = 0.45 * (0.5*math.sin(2*math.pi*180*t) + 0.3*math.sin(2*math.pi*360*t) + 0.2*math.sin(2*math.pi*540*t)
                    + 0.12*math.sin(2*math.pi*900*t) + 0.08*math.sin(2*math.pi*1500*t)) * (0.65 + 0.35*math.sin(2*math.pi*5*t))
    else:
        v = 0.0004 * (random.random() - 0.5)
    frames += struct.pack('<h', max(-32767, min(32767, int(v * 32767))))
w.writeframes(bytes(frames)); w.close()
PY
fi
echo "wrote $(pwd)/$out"
