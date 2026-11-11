/*
 * Mythos Voz: g_voice (see voicemanager.h).
 */

#include "voicemanager.h"

#include <cstddef>
#include <iterator>

#include <framework/luaengine/luainterface.h>

VoiceManager g_voice;

namespace
{
    constexpr size_t kVoiceEventsPerPoll = 64;
    // past this, events are dropped, except 'state' (a few per connection):
    // a lost 'closed' would leave Lua online with a dead socket
    constexpr size_t kVoiceEventsQueued = 4096;
}

VoiceEngine* VoiceManager::engine()
{
    if (!m_engine && !m_terminated)
        m_engine = createVoiceEngine([this](VoiceEvent&& event) { push(std::move(event)); });
    return m_engine.get();
}

void VoiceManager::push(VoiceEvent&& event)
{
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_events.size() >= kVoiceEventsQueued && event.type != "state")
        return;
    m_events.emplace_back(std::move(event));
    m_pending.store(true, std::memory_order_release);
}

void VoiceManager::poll()
{
    if (!m_engine)
        return;
    m_engine->poll();
    if (!m_pending.load(std::memory_order_acquire))
        return;

    std::vector<VoiceEvent> batch;
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        if (m_events.size() <= kVoiceEventsPerPoll) {
            batch.swap(m_events);
            m_pending.store(false, std::memory_order_relaxed);
        } else {
            const auto cut = m_events.begin() + static_cast<std::ptrdiff_t>(kVoiceEventsPerPoll);
            batch.assign(std::make_move_iterator(m_events.begin()), std::make_move_iterator(cut));
            m_events.erase(m_events.begin(), cut);
        }
    }

    for (const auto& event : batch) {
        if (event.type == "stats")
            m_stats = event.s;
        g_lua.callGlobalField("g_voice", "onVoiceEvent", event.type, event.s, event.a, event.b);
    }
}

void VoiceManager::terminate()
{
    m_terminated = true;
    if (m_engine) {
        m_engine->terminate();
        m_engine.reset();
    }
    std::lock_guard<std::mutex> lock(m_mutex);
    m_events.clear();
    m_pending.store(false, std::memory_order_relaxed);
}

bool VoiceManager::isSupported()
{
    auto* e = engine();
    return e && e->isSupported();
}

void VoiceManager::connect(const std::string& url, const std::string& token, const std::string& clientTag, const std::string& build)
{
    if (auto* e = engine())
        e->connect(url, token, clientTag, build);
}

void VoiceManager::disconnect()
{
    if (auto* e = engine())
        e->disconnect();
}

void VoiceManager::sendControl(const std::string& json)
{
    if (auto* e = engine())
        e->sendControl(json);
}

void VoiceManager::setTransmit(const int slot)
{
    if (auto* e = engine())
        e->setTransmit(slot);
}

void VoiceManager::setMode(const bool vad)
{
    if (auto* e = engine())
        e->setMode(vad);
}

void VoiceManager::setVadThreshold(const float db)
{
    if (auto* e = engine())
        e->setVadThreshold(db);
}

void VoiceManager::setPreset(const int preset)
{
    if (auto* e = engine())
        e->setPreset(preset);
}

void VoiceManager::setInputDevice(const std::string& name)
{
    if (auto* e = engine())
        e->setInputDevice(name);
}

void VoiceManager::setOutputDevice(const std::string& name)
{
    if (auto* e = engine())
        e->setOutputDevice(name);
}

std::vector<std::string> VoiceManager::getInputDevices()
{
    auto* e = engine();
    return e ? e->getInputDevices() : std::vector<std::string>();
}

std::vector<std::string> VoiceManager::getOutputDevices()
{
    auto* e = engine();
    return e ? e->getOutputDevices() : std::vector<std::string>();
}

void VoiceManager::setInputGain(const float gain)
{
    if (auto* e = engine())
        e->setInputGain(gain);
}

void VoiceManager::setOutputVolume(const float volume)
{
    if (auto* e = engine())
        e->setOutputVolume(volume);
}

void VoiceManager::setUserVolume(const int sid, const float volume)
{
    if (auto* e = engine())
        e->setUserVolume(sid, volume);
}

void VoiceManager::setSlotVolume(const int slot, const float volume)
{
    if (auto* e = engine())
        e->setSlotVolume(slot, volume);
}

void VoiceManager::setUserSpatial(const int sid, const float gain, const float pan)
{
    if (auto* e = engine())
        e->setUserSpatial(sid, gain, pan);
}

void VoiceManager::setDeafened(const bool on)
{
    if (auto* e = engine())
        e->setDeafened(on);
}

void VoiceManager::setSelfMuted(const bool on)
{
    if (auto* e = engine())
        e->setSelfMuted(on);
}

void VoiceManager::setMeter(const bool on)
{
    if (auto* e = engine())
        e->setMeter(on);
}

void VoiceManager::setPttMouse(const int button, const int slot)
{
    if (auto* e = engine())
        e->setPttMouse(button, slot);
}

void VoiceManager::setGlobalPtt(const int virtualKey)
{
    if (auto* e = engine())
        e->setGlobalPtt(virtualKey);
}

void VoiceManager::startLocalTest(const bool on)
{
    if (auto* e = engine())
        e->startLocalTest(on);
}

std::string VoiceManager::stats()
{
    if (auto* e = engine())
        e->requestStats();
    return m_stats;
}
