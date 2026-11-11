/*
 * Mythos Voz: the native voice engine (Windows; the Linux harness builds it
 * too): libopus, OpenAL capture and playback on a device of its own, and
 * ixwebsocket, all driven by one thread named "voz".
 *
 * Nothing exists until it is needed: no thread, device or socket before the
 * first connect(), microphone test or level meter. Then the voz thread:
 *
 *   loop {
 *     wait on a condition variable: 10 ms while capturing or playing, 50 ms
 *     while connected, 1 s while a device waits to be closed or a wanted
 *     microphone has not opened (tried again, device lists kept fresh),
 *     else until a command (woken at once by commands and by packets);
 *     commands; inbox (audio into each speaker's jitter buffer, control
 *     messages to the sink); capture (gain, level, push-to-talk / voice
 *     activation gate, Opus, send); playback (decode, concealment, OpenAL);
 *     housekeeping (idle decoders, the microphone closed 10 s after the
 *     last use in push-to-talk mode, device lists every 3 s, the global
 *     push-to-talk key on Windows)
 *   }
 *
 * Every OpenAL and socket call happens on that thread. The ixwebsocket
 * callback only copies what arrives into a mutex-guarded inbox (it never
 * owns the socket, so the last shared_ptr<ix::WebSocket> is never released
 * on its own thread: sockets are stopped and destroyed on the voz thread).
 *
 * The behaviour is the browser engine's (voiceengine.h lists it); the
 * jitter policy is jitterbuffer.h's.
 */

#pragma once

#include "audioio.h"
#include "voiceengine.h"

#include <cstdint>
#include <functional>
#include <memory>
#include <string>

struct NativeVoiceOptions
{
    // the microphone and the speakers; empty: OpenAL
    std::function<std::unique_ptr<AudioInput>()> makeInput;
    std::function<std::unique_ptr<AudioOutput>()> makeOutput;
    // PEM bundle tried first for wss:// (the client ships cacert.pem); the
    // system's certificate store is the fallback (and the only list when
    // this is empty or missing)
    std::string caFile;
    // 0 info, 1 warning, 2 error; may be called from the voz thread
    std::function<void(int level, const std::string& text)> log;
    // whether the global push-to-talk key is held; empty: voiceGlobalKeyHeld
    // (the harness stands in for the keyboard)
    std::function<bool(int virtualKey)> keyHeld;
    // test harness only, applied to received frames: the share dropped and
    // the most delay added (uniform, so frames can arrive out of order); a
    // stall holds every frame for stallMs once every stallEveryMs
    double lossRate = 0;
    int jitterMs = 0;
    int stallMs = 0;
    int stallEveryMs = 0;
    uint32_t seed = 1;
};

std::unique_ptr<VoiceEngine> createNativeVoiceEngine(VoiceEngine::Sink sink, NativeVoiceOptions options);

// Windows: whether a key is held now while another program has the focus
// (GetAsyncKeyState; in the client's own window, or another game client's,
// the in-game key is used); elsewhere always false
bool voiceGlobalKeyHeld(int virtualKey);
