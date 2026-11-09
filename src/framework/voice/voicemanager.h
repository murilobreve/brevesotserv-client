/*
 * Mythos Voz: g_voice, the Lua side of the voice engine.
 *
 * Nothing exists until Lua first calls it: the engine is made on the first
 * call (isSupported, connect, a device list...). Engine events are queued
 * (thread-safe) and raised on the game thread by poll(), at most 64 per
 * frame, as g_voice.onVoiceEvent(type, s, a, b); past 4096 queued events
 * only 'state' events are still taken. The method names and
 * arguments are the contract of modules/game_voice/engine_full.lua.
 */

#pragma once

#include "voiceengine.h"

#include <atomic>
#include <mutex>

//@bindsingleton g_voice
class VoiceManager
{
public:
    void poll();
    void terminate();

    bool isSupported();
    void connect(const std::string& url, const std::string& token, const std::string& clientTag, const std::string& build);
    void disconnect();
    void sendControl(const std::string& json);
    void setTransmit(int slot);
    void setMode(bool vad);
    void setVadThreshold(float db);
    void setPreset(int preset);
    void setInputDevice(const std::string& name);
    void setOutputDevice(const std::string& name);
    std::vector<std::string> getInputDevices();
    std::vector<std::string> getOutputDevices();
    void setInputGain(float gain);
    void setOutputVolume(float volume);
    void setUserVolume(int sid, float volume);
    void setSlotVolume(int slot, float volume);
    void setDeafened(bool on);
    void setSelfMuted(bool on);
    void setMeter(bool on);
    void setPttMouse(int button, int slot);
    void setGlobalPtt(int virtualKey);
    void startLocalTest(bool on);
    // the last counters the engine reported ("" before any); asks for new
    // ones, which come as a 'stats' event
    std::string stats();

private:
    VoiceEngine* engine();
    void push(VoiceEvent&& event);

    std::unique_ptr<VoiceEngine> m_engine;
    std::mutex m_mutex;
    std::vector<VoiceEvent> m_events;
    std::atomic<bool> m_pending{ false };
    std::string m_stats;
    bool m_terminated = false;
};

extern VoiceManager g_voice;
