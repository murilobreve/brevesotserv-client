/*
 * Mythos Voz: the voice engine interface shared by the builds.
 *
 * VoiceManager (g_voice) owns one engine and is the only thing Lua sees. An
 * engine reports through a Sink that may be called from any thread; the
 * manager queues the events and raises them in Lua on the game thread as
 * g_voice.onVoiceEvent(type, s, a, b) (modules/game_voice/engine_full.lua).
 *
 * Engines: voiceengine_web.cpp (browser: the page's MythosVoice),
 * voiceengine_native.cpp (Windows, and any desktop with VOICE_NATIVE:
 * libopus, OpenAL, ixwebsocket) and voiceengine_null.cpp (no audio:
 * isSupported() is false and the Lua side falls back to its presence-only
 * engine).
 *
 * Only the standard library here, so the engine files build on their own.
 */

#pragma once

#include <functional>
#include <memory>
#include <string>
#include <vector>

struct VoiceEvent
{
    // state:   s = connecting|open|closed, a = WebSocket close code
    // ctl:     s = one control message from the relay (JSON text)
    // spk:     a = speaker sid, b = 1 speaking / 0 stopped (edges only)
    // talk:    a = slot we transmit on (0-3), -1 when the gate closes
    // level:   a = microphone level in dBFS (10 Hz, only while metering)
    // mic:     s = ok|denied|nodevice|encoder (the encoder failed: listen only)
    // devices: the device lists changed (read them with get*Devices)
    // stats:   s = JSON counters; caps: s = JSON of what the engine can do
    std::string type;
    std::string s;
    int a = 0;
    int b = 0;
};

class VoiceEngine
{
public:
    // thread-safe; may be called from any thread
    using Sink = std::function<void(VoiceEvent&&)>;

    virtual ~VoiceEngine() = default;

    virtual bool isSupported() = 0;

    // opens the relay socket and sends the hello once it is open; a socket
    // replaced by a new connect() or closed by disconnect() reports nothing
    virtual void connect(const std::string& url, const std::string& token, const std::string& clientTag, const std::string& build) = 0;
    virtual void disconnect() = 0;
    virtual void sendControl(const std::string& json) = 0;

    // The Lua side sends every setting again whenever one changes (each step
    // of a slider): a setter whose value did not change must do nothing, in
    // particular setInputDevice must not reopen the microphone, and setMeter
    // must not bring up a permission prompt.
    //
    // Behaviour the browser engine has and the native one must match:
    // - voice activation listens only while connected, in a room and not
    //   self-muted (in no room nothing is captured or sent, no 'talk'); it
    //   talks in the first room joined, slots 0 to 3 (the one talk key's
    //   place); so does the Windows background key;
    // - frames for a slot with no room are not sent; Opus over the welcome's
    //   lim.pl is not sent (the relay counts it as abuse);
    // - the side mouse button and the push-to-talk key are held apart: letting
    //   go of one leaves the other talking;
    // - an output stream put to sleep when idle is woken by every path that
    //   needs the capture (mic test, meter, voice activation, the mouse
    //   button), not only by the key and by incoming voice;
    // - a saved device that could not be resolved when the microphone opened
    //   is moved to once it can be; a missing microphone is tried again when
    //   a device appears;
    // - disconnect() keeps the level meter going (the settings window may be
    //   open); terminate() stops it.
    virtual void setTransmit(int slot) = 0; // 0 party, 1 guild, 2 public/stage/echo, 3 near; -1 stop
    virtual void setMode(bool vad) = 0; // voice activation instead of push-to-talk
    virtual void setVadThreshold(float db) = 0;
    virtual void setPreset(int preset) = 0; // 0 normal, 1 eco, 2 high
    virtual void setInputDevice(const std::string& name) = 0; // "" = system default
    virtual void setOutputDevice(const std::string& name) = 0;
    virtual std::vector<std::string> getInputDevices() = 0;
    virtual std::vector<std::string> getOutputDevices() = 0;
    virtual void setInputGain(float gain) = 0; // 0-2
    virtual void setOutputVolume(float volume) = 0; // 0-2
    virtual void setUserVolume(int sid, float volume) = 0; // 0-2, one speaker
    virtual void setSlotVolume(int slot, float volume) = 0; // 0-2, one room slot 0-3
    // A near speaker's place, for its frames on slot 3 only (frames of the
    // same speaker on another slot play centred, at full gain): gain 0-1 and
    // pan -1 (left) .. 1 (right), both clamped; 1 and 0 until set. The
    // effective gain on slot 3 is master x slot volume x user volume x this
    // gain; the pan is constant power (the browser mixes it so; the native
    // engine places the source and OpenAL pans it for the output, which on
    // stereo is close to that); changes are smoothed over ~50 ms.
    // Forgotten with the connection (sids are per relay session). A speaker
    // never given one, and every other slot, costs nothing more per frame.
    virtual void setUserSpatial(int sid, float gain, float pan) = 0;
    virtual void setDeafened(bool on) = 0;
    virtual void setSelfMuted(bool on) = 0;
    virtual void setMeter(bool on) = 0;
    virtual void setPttMouse(int button, int slot) = 0; // browser: button 3 or 4, slot 0-3, -1 = off
    virtual void setGlobalPtt(int virtualKey) = 0; // Windows: 0 = off
    virtual void startLocalTest(bool on) = 0;
    virtual void requestStats() = 0; // answered by a 'stats' event

    // engine work on the game thread, once per frame; must be cheap when idle
    virtual void poll() {}
    // the game is closing: the socket, the microphone and the meter all stop
    virtual void terminate() = 0;
};

// The engine of this build: defined by exactly one of voiceengine_web.cpp,
// voiceengine_native.cpp and voiceengine_null.cpp.
std::unique_ptr<VoiceEngine> createVoiceEngine(VoiceEngine::Sink sink);
