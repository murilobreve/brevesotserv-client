/*
 * Mythos Voz: the browser engine. All audio runs in the page
 * (browser/voice/mythos-voice.js, pasted into index.html at build time):
 * this file only carries JSON both ways and never waits on the page.
 *
 * Commands, game thread -> page: a malloc'd copy of the JSON text through
 * MAIN_THREAD_ASYNC_EM_ASM (the page frees it with the exported _free) to
 * MythosVoice.cmd. Calls from one thread run on the page in the order sent.
 *
 * Events, page -> game thread: the page batches its events (one JSON array
 * per microtask) and calls the exported otc_voice_event on the browser's
 * main thread, which only copies the text into a mutex-guarded inbox.
 * poll(), on the game thread, parses it and hands the events to the sink.
 * A full inbox (the game thread stopped polling: a hidden tab stops its
 * frames) refuses the batch with 0; the page keeps it and tries again, and
 * if that goes on it ends the connection itself, so the game later sees one
 * 'closed' instead of a gap in the events.
 *
 * Each connect() carries a generation number that the page echoes on the
 * socket's events; events of an older socket (one replaced or closed by us
 * meanwhile) are dropped here, so a late 'closed' never ends a newer
 * connection.
 *
 * The one synchronous call is isSupported(), a single MAIN_THREAD_EM_ASM_INT
 * until the page has a definite answer.
 */

#ifdef __EMSCRIPTEN__

#include "voiceengine.h"

#include <atomic>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <utility>

#include <emscripten/emscripten.h>
#include <nlohmann/json.hpp>

namespace
{
    constexpr size_t kWebVoiceMaxBatches = 1024;
    constexpr size_t kWebVoiceMaxBatchBytes = 512 * 1024;

    // event batches from the page, filled on the browser's main thread
    struct WebVoiceInbox
    {
        std::mutex mutex;
        std::vector<std::string> batches;
        std::atomic<bool> pending{ false };
    };

    WebVoiceInbox& webVoiceInbox()
    {
        static WebVoiceInbox inbox;
        return inbox;
    }

    std::string webVoiceString(const nlohmann::json& o, const char* key)
    {
        const auto it = o.find(key);
        return it != o.end() && it->is_string() ? it->get<std::string>() : std::string();
    }

    int webVoiceInt(const nlohmann::json& o, const char* key)
    {
        const auto it = o.find(key);
        if (it == o.end() || !it->is_number())
            return 0;
        const double v = it->get<double>();
        if (!(v > -1e9 && v < 1e9)) // also NaN
            return 0;
        return static_cast<int>(std::lround(v));
    }

    std::vector<std::string> webVoiceStrings(const nlohmann::json& o, const char* key)
    {
        std::vector<std::string> out;
        const auto it = o.find(key);
        if (it == o.end() || !it->is_array())
            return out;
        for (const auto& v : *it) {
            if (v.is_string() && out.size() < 32)
                out.push_back(v.get<std::string>());
        }
        return out;
    }

    nlohmann::json webVoiceCommand(const char* op)
    {
        nlohmann::json c = nlohmann::json::object();
        c["op"] = op;
        return c;
    }

    class WebVoiceEngine final : public VoiceEngine
    {
    public:
        explicit WebVoiceEngine(Sink sink) : m_sink(std::move(sink)) {}

        bool isSupported() override
        {
            if (m_support < 0) {
                // 1 yes, 0 no, 2 still checking (the codec query is a promise)
                // clang-format off
                const int s = MAIN_THREAD_EM_ASM_INT({
                    var v = window["MythosVoice"];
                    return v && v["support"] ? v["support"]() : 0;
                });
                // clang-format on
                if (s == 0 || s == 1)
                    m_support = s;
                return s == 1;
            }
            return m_support == 1;
        }

        void connect(const std::string& url, const std::string& token, const std::string& clientTag, const std::string& build) override
        {
            auto c = webVoiceCommand("connect");
            c["url"] = url;
            c["tok"] = token;
            c["cl"] = clientTag;
            c["b"] = build;
            c["g"] = ++m_gen;
            send(c);
        }

        void disconnect() override
        {
            ++m_gen; // whatever the old socket still says is dropped
            send(webVoiceCommand("disconnect"));
        }

        void sendControl(const std::string& json) override
        {
            auto c = webVoiceCommand("ctl");
            c["json"] = json;
            send(c);
        }

        void setTransmit(const int slot) override
        {
            auto c = webVoiceCommand("tx");
            c["slot"] = slot;
            send(c);
        }

        void setMode(const bool vad) override
        {
            auto c = webVoiceCommand("mode");
            c["vad"] = vad;
            send(c);
        }

        void setVadThreshold(const float db) override
        {
            auto c = webVoiceCommand("vad");
            c["db"] = db;
            send(c);
        }

        void setPreset(const int preset) override
        {
            auto c = webVoiceCommand("preset");
            c["p"] = preset;
            send(c);
        }

        void setInputDevice(const std::string& name) override
        {
            auto c = webVoiceCommand("indev");
            c["id"] = name;
            send(c);
        }

        void setOutputDevice(const std::string& name) override
        {
            auto c = webVoiceCommand("outdev");
            c["id"] = name;
            send(c);
        }

        std::vector<std::string> getInputDevices() override { return m_inputs; }
        std::vector<std::string> getOutputDevices() override { return m_outputs; }

        void setInputGain(const float gain) override
        {
            auto c = webVoiceCommand("ingain");
            c["x"] = gain;
            send(c);
        }

        void setOutputVolume(const float volume) override
        {
            auto c = webVoiceCommand("outvol");
            c["x"] = volume;
            send(c);
        }

        void setUserVolume(const int sid, const float volume) override
        {
            auto c = webVoiceCommand("uvol");
            c["sid"] = sid;
            c["x"] = volume;
            send(c);
        }

        void setSlotVolume(const int slot, const float volume) override
        {
            auto c = webVoiceCommand("svol");
            c["slot"] = slot;
            c["x"] = volume;
            send(c);
        }

        void setDeafened(const bool on) override
        {
            auto c = webVoiceCommand("deaf");
            c["on"] = on;
            send(c);
        }

        void setSelfMuted(const bool on) override
        {
            auto c = webVoiceCommand("smute");
            c["on"] = on;
            send(c);
        }

        void setMeter(const bool on) override
        {
            auto c = webVoiceCommand("meter");
            c["on"] = on;
            send(c);
        }

        void setPttMouse(const int button, const int slot) override
        {
            auto c = webVoiceCommand("pttMouse");
            c["btn"] = button;
            c["slot"] = slot;
            send(c);
        }

        void setGlobalPtt(int) override {} // the browser has no background keys

        void startLocalTest(const bool on) override
        {
            auto c = webVoiceCommand("test");
            c["on"] = on;
            send(c);
        }

        void requestStats() override { send(webVoiceCommand("stats")); }

        void poll() override
        {
            auto& inbox = webVoiceInbox();
            if (!inbox.pending.load(std::memory_order_acquire))
                return;
            std::vector<std::string> batches;
            {
                std::lock_guard<std::mutex> lock(inbox.mutex);
                batches.swap(inbox.batches);
                inbox.pending.store(false, std::memory_order_relaxed);
            }
            for (const auto& text : batches)
                parseBatch(text);
        }

        void terminate() override
        {
            ++m_gen;
            auto c = webVoiceCommand("disconnect");
            c["end"] = true; // the level meter stops too
            send(c);
        }

    private:
        static void send(const nlohmann::json& command)
        {
            const std::string text = command.dump(-1, ' ', false, nlohmann::json::error_handler_t::replace);
            auto* copy = static_cast<char*>(std::malloc(text.size() + 1));
            if (!copy)
                return;
            std::memcpy(copy, text.c_str(), text.size() + 1);
            // clang-format off
            MAIN_THREAD_ASYNC_EM_ASM({
                var text = UTF8ToString($0);
                _free($0);
                var v = window["MythosVoice"];
                if (v) v["cmd"](text);
            }, copy);
            // clang-format on
        }

        void parseBatch(const std::string& text)
        {
            const auto batch = nlohmann::json::parse(text, nullptr, false);
            if (!batch.is_array())
                return;
            for (const auto& item : batch) {
                if (!item.is_object())
                    continue;
                VoiceEvent event;
                event.type = webVoiceString(item, "t");
                if (event.type.empty())
                    continue;
                const int gen = webVoiceInt(item, "g");
                if (gen != 0 && gen != m_gen)
                    continue; // a socket replaced or closed meanwhile
                if (event.type == "devices") {
                    m_inputs = webVoiceStrings(item, "i");
                    m_outputs = webVoiceStrings(item, "o");
                }
                event.s = webVoiceString(item, "s");
                event.a = webVoiceInt(item, "a");
                event.b = webVoiceInt(item, "b");
                m_sink(std::move(event));
            }
        }

        Sink m_sink;
        int m_support = -1;
        int m_gen = 0;
        std::vector<std::string> m_inputs;
        std::vector<std::string> m_outputs;
    };
}

// Called by the page (Module._otc_voice_event) on the browser's main thread
// with one JSON array of events; the page frees the text after the call.
// 1: taken; 0: the inbox is full (the game thread stopped polling), the page
// keeps the batch and tries again later; -1: refused for good (too big).
extern "C" EMSCRIPTEN_KEEPALIVE int otc_voice_event(const char* json)
{
    if (!json)
        return -1;
    const size_t n = std::strlen(json);
    if (n > kWebVoiceMaxBatchBytes)
        return -1;
    auto& inbox = webVoiceInbox();
    std::lock_guard<std::mutex> lock(inbox.mutex);
    if (inbox.batches.size() >= kWebVoiceMaxBatches)
        return 0;
    inbox.batches.emplace_back(json, n);
    inbox.pending.store(true, std::memory_order_release);
    return 1;
}

std::unique_ptr<VoiceEngine> createVoiceEngine(VoiceEngine::Sink sink)
{
    return std::make_unique<WebVoiceEngine>(std::move(sink));
}

#endif // __EMSCRIPTEN__
