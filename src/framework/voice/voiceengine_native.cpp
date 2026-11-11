/*
 * Mythos Voz: the native voice engine (see voiceengine_native.h).
 *
 * Threads: the caller's (the game thread: the VoiceEngine methods), "voz"
 * (everything else), ixwebsocket's own (callbacks into the inbox only), and
 * OpenAL Soft's mixer and capture threads.
 *
 * The VoiceEngine methods turn each call into a command for the voz thread.
 * Before that thread exists (settings sent at startup, before any connect)
 * a command runs at once on the caller's thread: commands only change
 * state, the voz thread's tick does the device and socket work, so that is
 * safe; once started, the thread runs until terminate().
 *
 * With -DVOICE_STANDALONE (tools/voz-native-test) this file needs no part of
 * the framework; createVoiceEngine() (g_voice's factory) is only built in
 * the client.
 */

#include "voiceengine_native.h"

#include "jitterbuffer.h"
#include "voicecodec.h"
#include "voiceprotocol.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstring>
#include <deque>
#include <exception>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <limits>
#include <map>
#include <mutex>
#include <random>
#include <thread>
#include <utility>
#include <vector>

#include <ixwebsocket/IXNetSystem.h>
#include <ixwebsocket/IXSetThreadName.h>
#include <ixwebsocket/IXWebSocket.h>
#include <nlohmann/json.hpp>

namespace
{
    using json = nlohmann::json;

    constexpr int kRate = 48000;
    constexpr int kTestSid = 65536; // outside the relay's u16 sids
    constexpr int kTestSlot = 2;
    constexpr int kSlots = voiceproto::kSlots; // 0 party, 1 guild, 2 public, 3 near
    constexpr int kNearSlot = 3;
    constexpr int64_t kPlaceRampMs = 50; // a near speaker's new place: there in this long
    constexpr int kMaxQueued = 8; // buffers one stream holds in OpenAL (4) or the harness (4)
    constexpr size_t kMaxSpeakers = 8; // decoders and OpenAL streams
    constexpr int kLeadBuffers = 2; // decoded frames queued in OpenAL per speaker
    constexpr int64_t kSpeakerIdleMs = 10000; // decoder freed
    constexpr int64_t kSpkGapMs = 300; // speaking off without frames
    constexpr int64_t kMicIdleMs = 10000; // push-to-talk: closed 10 s after the last use
    constexpr int64_t kMicRetryPressMs = 5000; // a refused microphone, asked by a press
    constexpr int64_t kMicRetryMs = 15000; // ... asked by voice activation or the meter
    constexpr int64_t kOutRetryMs = 5000;
    constexpr int64_t kOutIdleCloseMs = 30000;
    constexpr int64_t kDevicePollMs = 3000;
    constexpr int64_t kHouseMs = 1000;
    constexpr int64_t kSlowDeviceMs = 50; // a device call that long is counted (stats dev.slow)
    constexpr int64_t kSlowDeviceLogMs = 100; // ... and logged when it is a new worst (OpenAL holds 80 ms)
    constexpr int64_t kGlobalTxMaxMs = 60000; // the background key held longer: released
    constexpr int64_t kEncCoolMs = 2000;
    constexpr size_t kSendBacklog = 16384; // bytes waiting in the socket: audio is dropped
    constexpr size_t kInboxAudioMax = 512;
    constexpr int kLevelWindow = 4800; // 100 ms: the meter's 10 Hz

    bool contains(const std::vector<std::string>& list, const std::string& name)
    {
        return !name.empty() && std::find(list.begin(), list.end(), name) != list.end();
    }

    int64_t nowMs()
    {
        using namespace std::chrono;
        return duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count();
    }

    float clampGain(const float x, const float d)
    {
        return std::isfinite(x) ? std::clamp(x, 0.0f, 2.0f) : d;
    }

    bool validUtf8(const std::string& s)
    {
        size_t i = 0;
        const size_t n = s.size();
        while (i < n) {
            const auto c = static_cast<unsigned char>(s[i]);
            size_t len = 0;
            if (c < 0x80)
                len = 1;
            else if ((c & 0xE0) == 0xC0 && c >= 0xC2)
                len = 2;
            else if ((c & 0xF0) == 0xE0)
                len = 3;
            else if ((c & 0xF8) == 0xF0 && c <= 0xF4)
                len = 4;
            else
                return false;
            if (i + len > n)
                return false;
            for (size_t k = 1; k < len; ++k) {
                if ((static_cast<unsigned char>(s[i + k]) & 0xC0) != 0x80)
                    return false;
            }
            i += len;
        }
        return true;
    }

    // the client's text is Latin-1; the relay's is UTF-8
    std::string latin1ToUtf8(const std::string& s)
    {
        std::string out;
        out.reserve(s.size() + 8);
        for (const char ch : s) {
            const auto c = static_cast<unsigned char>(ch);
            if (c < 0x80) {
                out.push_back(static_cast<char>(c));
            } else {
                out.push_back(static_cast<char>(0xC0 | (c >> 6)));
                out.push_back(static_cast<char>(0x80 | (c & 0x3F)));
            }
        }
        return out;
    }

    int16_t saturate(const float x)
    {
        if (x > 32767.0f)
            return 32767;
        if (x < -32768.0f)
            return -32768;
        return static_cast<int16_t>(std::lrint(x));
    }

    double dbOf(const double sum, const int n)
    {
        return 10.0 * std::log10(sum / (std::max)(1, n) + 1e-12);
    }

    bool fileExists(const std::string& utf8Path)
    {
        if (utf8Path.empty())
            return false;
        std::error_code ec;
        const std::u8string u8(utf8Path.begin(), utf8Path.end());
        return std::filesystem::is_regular_file(std::filesystem::path(u8), ec);
    }

    // the bundle for ixwebsocket: the certificates themselves, read here
    // through a wide path. Its mbedTLS (the Windows build) opens a file name
    // with fopen, which reads it in the ANSI code page, so a client folder
    // with an accent (a profile named with a tilde) is never found; a caFile
    // holding "-----BEGIN CERTIFICATE-----" is parsed from memory by both
    // backends. The path itself when the file does not read as PEM.
    std::string caBundle(const std::string& utf8Path)
    {
        const std::u8string u8(utf8Path.begin(), utf8Path.end());
        std::ifstream f(std::filesystem::path(u8), std::ios::binary);
        std::string text((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
        if (text.find("-----BEGIN CERTIFICATE-----") == std::string::npos)
            return utf8Path;
        return text;
    }

    // an ixwebsocket connect error where another certificate list could help
    bool tlsError(const std::string& reason)
    {
        for (const char* key : { "SSL", "TLS", "handshake", "certificate", "Certificate", "CA file", "CA from", "x509",
                                 "X509", "verif" }) {
            if (reason.find(key) != std::string::npos)
                return true;
        }
        return false;
    }

    // one item from the socket's thread
    struct Inbound
    {
        enum class Kind : uint8_t
        {
            Audio,
            Text,
            Open,
            Closed,
        };
        Kind kind = Kind::Audio;
        uint32_t gen = 0;
        // Audio
        uint16_t sid = 0;
        uint8_t flags = 0;
        uint8_t seq = 0;
        uint8_t len = 0;
        uint8_t data[voiceproto::kMaxOpus] = {};
        int64_t at = 0;
        // Text, or Closed's reason
        std::string text;
        // Closed
        int code = 0;
        bool tlsRetry = false;
    };

    // shared by the engine, the voz thread and the socket callbacks (which
    // hold it by shared_ptr: it outlives a socket the engine dropped)
    struct Box
    {
        std::mutex mutex;
        std::condition_variable cv;
        std::vector<std::function<void()>> cmds;
        std::deque<Inbound> in;
        size_t audio = 0;
        bool stop = false;
        // counted by the socket thread, under the mutex
        uint64_t binMsgs = 0;
        uint64_t binBytes = 0;
        uint64_t bad = 0;
        uint64_t inboxDrops = 0;
    };

    struct Speaker
    {
        JitterBuffer jb{ 40 };
        OpusDec dec;
        int stream = -1;
        int64_t lastAt = 0;
        bool queuedSpurt = false; // something went to OpenAL in this spurt
        // the slots of the buffers queued in OpenAL, the one playing first:
        // the gain and the place follow the frame being heard (frames carry
        // their slot), not the last one that arrived
        uint8_t queued[kMaxQueued] = {};
        int queuedN = 0;
        int playSlot = 0; // the slot of the buffer playing now (or the last one)
    };

    // a near speaker's place (setUserSpatial), for its slot-3 frames: the
    // target, and what is heard now, moving to it in kPlaceRampMs
    struct Place
    {
        float gain = 1.0f;
        float pan = 0.0f;
        float curGain = 1.0f;
        float curPan = 0.0f;
        float fromGain = 1.0f;
        float fromPan = 0.0f;
        int64_t rampAt = 0;
        bool ramp = false;
    };

    struct SpeakingEdge
    {
        bool on = false;
        int64_t last = 0;
    };

    struct Conn
    {
        std::shared_ptr<ix::WebSocket> ws;
        uint32_t gen = 0;
        bool open = false;
        std::string url;
        std::string token;
        std::string clientTag;
        std::string build;
        bool bundle = false; // this try verifies with the shipped bundle
        bool retried = false; // the other certificate list was tried already
    };

    enum class MicState : uint8_t
    {
        Off,
        On,
        NoDevice,
        Denied,
    };

    const char* micName(const MicState s)
    {
        switch (s) {
            case MicState::On:
                return "on";
            case MicState::NoDevice:
                return "nodevice";
            case MicState::Denied:
                return "denied";
            default:
                return "off";
        }
    }

    struct Counters
    {
        uint64_t upF = 0, upB = 0, upDrop = 0, upBig = 0, upNoRoom = 0;
        uint64_t encOut = 0, encErr = 0, encNew = 0;
        uint64_t inF = 0, inOpus = 0, inEnd = 0, deafDrop = 0;
        uint64_t decOut = 0, decErr = 0, decNew = 0, conceal = 0;
        uint64_t ctlIn = 0, ctlOut = 0, sockets = 0, tlsRetries = 0;
        uint64_t underruns = 0, micMoves = 0, outOpens = 0;
        uint64_t injLost = 0, injDelayed = 0, injStalled = 0;
        uint64_t devSlow = 0;
        int64_t micOpenMaxMs = 0, outOpenMaxMs = 0, listMaxMs = 0;
    };

    class NativeVoiceEngine final : public VoiceEngine
    {
    public:
        NativeVoiceEngine(Sink sink, NativeVoiceOptions options)
            : m_sink(std::move(sink)), m_opt(std::move(options)), m_box(std::make_shared<Box>()), m_rng(m_opt.seed)
        {
            m_in = m_opt.makeInput ? m_opt.makeInput() : createOpenALCapture();
            m_out = m_opt.makeOutput ? m_opt.makeOutput() : createOpenALPlayback();
            m_supported = m_in && m_out && m_out->supported();
            m_frame.assign(voicecodec::preset(0).frameSamples, 0);
            m_prev.assign(m_frame.size(), 0);
            m_scratch.assign(voicecodec::kMaxFrameSamples, 0);
            m_inject = m_opt.lossRate > 0 || m_opt.jitterMs > 0 || (m_opt.stallMs > 0 && m_opt.stallEveryMs > 0);
            json caps = { { "ok", m_supported }, { "engine", "native" }, { "presets", { 1, 1, 1 } }, { "sink", true },
#ifdef _WIN32
                          { "globalPtt", true } };
#else
                          { "globalPtt", false } };
#endif
            emit("caps", caps.dump());
        }

        ~NativeVoiceEngine() override { terminate(); }

        bool isSupported() override { return m_supported; }

        void connect(const std::string& url, const std::string& token, const std::string& clientTag,
                     const std::string& build) override
        {
            if (m_terminated || !m_supported)
                return;
            ensureThread();
            if (!m_thread.joinable())
                return; // the socket lives on the voz thread only
            post([this, url, token, clientTag, build] { doConnect(url, token, clientTag, build); });
        }

        void disconnect() override
        {
            post([this] { doDisconnect(false); });
        }

        void sendControl(const std::string& text) override
        {
            post([this, text] { doSendControl(text); });
        }

        void setTransmit(const int slot) override
        {
            const int k = slot >= 0 && slot < kSlots ? slot : -1;
            post([this, k] { m_keyTx = k >= 0 && (m_deaf || m_smute) ? -1 : k; });
        }

        void setMode(const bool vad) override
        {
            if (m_ui.vad == static_cast<int>(vad))
                return;
            m_ui.vad = vad;
            post([this, vad] { m_vad = vad; });
        }

        void setVadThreshold(const float db) override
        {
            const float v = std::isfinite(db) ? std::clamp(db, -90.0f, 0.0f) : -45.0f;
            if (m_ui.vadDb == v)
                return;
            m_ui.vadDb = v;
            post([this, v] { m_vadDb = v; });
        }

        void setPreset(const int preset) override
        {
            const int p = std::clamp(preset, 0, 2);
            if (m_ui.preset == p)
                return;
            m_ui.preset = p;
            post([this, p] { m_preset = p; });
        }

        void setInputDevice(const std::string& name) override
        {
            if (m_ui.inDevSet && m_ui.inDev == name)
                return;
            m_ui.inDevSet = true;
            m_ui.inDev = name;
            post([this, name] {
                if (name == m_inDev)
                    return;
                m_inDev = name;
                if (m_in->isOpen())
                    m_micReopen = true; // another device: the microphone opens again on it
            });
        }

        void setOutputDevice(const std::string& name) override
        {
            if (m_ui.outDevSet && m_ui.outDev == name)
                return;
            m_ui.outDevSet = true;
            m_ui.outDev = name;
            post([this, name] {
                if (name == m_outDev)
                    return;
                m_outDev = name;
                if (m_out->isOpen())
                    m_outReopen = true;
            });
        }

        std::vector<std::string> getInputDevices() override { return deviceList(true); }
        std::vector<std::string> getOutputDevices() override { return deviceList(false); }

        void setInputGain(const float gain) override
        {
            const float g = clampGain(gain, 1.0f);
            if (m_ui.inGain == g)
                return;
            m_ui.inGain = g;
            post([this, g] { m_inGain = g; });
        }

        void setOutputVolume(const float volume) override
        {
            const float g = clampGain(volume, 1.0f);
            if (m_ui.outVol == g)
                return;
            m_ui.outVol = g;
            post([this, g] { m_outVol = g; });
        }

        void setUserVolume(const int sid, const float volume) override
        {
            // no change check here: the voz thread forgets these with each
            // connection (sids belong to one relay session) and the game
            // sends them again
            const float g = clampGain(volume, 1.0f);
            post([this, sid, g] {
                if (g == 1.0f)
                    m_users.erase(sid);
                else
                    m_users[sid] = g;
            });
        }

        void setSlotVolume(const int slot, const float volume) override
        {
            if (slot < 0 || slot >= kSlots)
                return;
            const float g = clampGain(volume, 1.0f);
            if (m_ui.slots[slot] == g)
                return;
            m_ui.slots[slot] = g;
            post([this, slot, g] { m_slotGain[slot] = g; });
        }

        void setUserSpatial(const int sid, const float gain, const float pan) override
        {
            // no change check here: forgotten with each connection, as the
            // user volumes (Lua sends only changes, a few a second)
            const float g = std::isfinite(gain) ? std::clamp(gain, 0.0f, 1.0f) : 1.0f;
            const float p = std::isfinite(pan) ? std::clamp(pan, -1.0f, 1.0f) : 0.0f;
            post([this, sid, g, p] { placeSpeaker(sid, g, p, nowMs()); });
        }

        void setDeafened(const bool on) override
        {
            if (m_ui.deaf == static_cast<int>(on))
                return;
            m_ui.deaf = on;
            post([this, on] {
                m_deaf = on;
                if (on)
                    m_keyTx = -1;
            });
        }

        void setSelfMuted(const bool on) override
        {
            if (m_ui.smute == static_cast<int>(on))
                return;
            m_ui.smute = on;
            post([this, on] {
                m_smute = on;
                if (on)
                    m_keyTx = -1;
            });
        }

        void setMeter(const bool on) override
        {
            if (m_ui.meter == static_cast<int>(on))
                return;
            m_ui.meter = on;
            if (on && m_supported && !m_terminated)
                ensureThread();
            post([this, on] { m_meter = on; });
        }

        void setPttMouse(int, int) override {} // the browser's side mouse buttons

        void setGlobalPtt(const int virtualKey) override
        {
            const int vk = virtualKey > 0 && virtualKey < 256 ? virtualKey : 0;
            if (m_ui.vk == vk)
                return;
            m_ui.vk = vk;
            post([this, vk] {
                m_globalVk = vk;
                if (!vk) {
                    m_globalHeld = false;
                    m_globalBlocked = false;
                }
            });
        }

        void startLocalTest(const bool on) override
        {
            if (on && m_supported && !m_terminated)
                ensureThread();
            post([this, on] {
                m_test = on;
                if (!on)
                    dropSpeaker(kTestSid);
            });
        }

        void requestStats() override
        {
            post([this] { emit("stats", snapshot().dump(-1, ' ', false, json::error_handler_t::replace)); });
        }

        void terminate() override
        {
            if (m_terminated)
                return;
            m_terminated = true;
            if (!m_thread.joinable())
                return;
            {
                std::lock_guard<std::mutex> lock(m_box->mutex);
                m_box->stop = true;
            }
            m_box->cv.notify_all();
            if (m_thread.get_id() == std::this_thread::get_id()) {
                m_thread.detach(); // an exit() from the voz thread itself: it stops on return
                return;
            }
            m_thread.join();
        }

    private:
        // -- the caller's side -------------------------------------------------

        struct Ui
        {
            int vad = -1;
            float vadDb = NAN;
            int preset = -1;
            bool inDevSet = false;
            bool outDevSet = false;
            std::string inDev;
            std::string outDev;
            float inGain = NAN;
            float outVol = NAN;
            float slots[kSlots] = { NAN, NAN, NAN, NAN };
            int deaf = -1;
            int smute = -1;
            int meter = -1;
            int vk = -1;
        };

        void ensureThread()
        {
            if (m_thread.joinable() || m_terminated)
                return;
            try {
                m_thread = std::thread([this] { run(); });
            } catch (const std::exception& e) {
                log(2, std::string("voice: the voice thread could not start: ") + e.what());
            }
        }

        void post(std::function<void()> fn)
        {
            if (m_terminated)
                return;
            if (!m_thread.joinable()) {
                fn(); // no voice thread yet: only state changes, nothing is open
                return;
            }
            {
                std::lock_guard<std::mutex> lock(m_box->mutex);
                m_box->cmds.push_back(std::move(fn));
            }
            m_box->cv.notify_one();
        }

        std::vector<std::string> deviceList(const bool input)
        {
            if (!m_in || !m_out)
                return {};
            const int64_t t = nowMs();
            {
                std::lock_guard<std::mutex> lock(m_devMutex);
                // the voz thread lists them every 3 s while it uses audio or a
                // connection; an idle one does not, and then they are listed here
                if (m_listed && m_thread.joinable() && t - m_listedAt < kDevicePollMs + 2 * kHouseMs)
                    return input ? m_inList : m_outList;
            }
            auto ins = m_in->devices();
            auto outs = m_out->devices();
            std::lock_guard<std::mutex> lock(m_devMutex);
            m_inList = std::move(ins);
            m_outList = std::move(outs);
            m_listed = true;
            m_listedAt = t;
            return input ? m_inList : m_outList;
        }

        void emit(const char* type, std::string s = std::string(), const int a = 0, const int b = 0)
        {
            VoiceEvent e;
            e.type = type;
            e.s = std::move(s);
            e.a = a;
            e.b = b;
            if (m_sink)
                m_sink(std::move(e));
        }

        void log(const int level, const std::string& text)
        {
            if (m_opt.log)
                m_opt.log(level, text);
        }

        // -- the voz thread ----------------------------------------------------

        void run()
        {
            ix::setThreadName("voz");
            ix::initNetSystem();
            int64_t lastErrorLog = -100000;
            for (;;) {
                std::vector<std::function<void()>> cmds;
                std::deque<Inbound> in;
                bool stop = false;
                {
                    std::unique_lock<std::mutex> lock(m_box->mutex);
                    const auto ready = [this] { return m_box->stop || !m_box->cmds.empty() || !m_box->in.empty(); };
                    const int64_t wait = waitMs(nowMs());
                    if (wait < 0)
                        m_box->cv.wait(lock, ready);
                    else if (wait > 0)
                        m_box->cv.wait_for(lock, std::chrono::milliseconds(wait), ready);
                    cmds.swap(m_box->cmds);
                    in.swap(m_box->in);
                    m_box->audio = 0;
                    stop = m_box->stop;
                }
                try {
                    for (auto& c : cmds)
                        c();
                    if (stop)
                        break;
                    const int64_t t = nowMs();
                    for (auto& item : in)
                        onInbound(item, t);
                    tick(t);
                } catch (const std::exception& e) {
                    noteError(e.what(), lastErrorLog);
                } catch (...) {
                    noteError("unknown exception", lastErrorLog);
                }
            }
            try {
                shutdownAll();
            } catch (...) {
                // closing anyway
            }
            ix::uninitNetSystem();
        }

        void noteError(const std::string& what, int64_t& lastLog)
        {
            ++m_errors;
            m_lastError = what.substr(0, 200);
            const int64_t t = nowMs();
            if (t - lastLog > 10000) {
                lastLog = t;
                log(2, "voice: " + m_lastError);
            }
        }

        int64_t waitMs(const int64_t t) const
        {
            int64_t w = -1;
            if (m_gate || (m_in->isOpen() && capturing()) || anySpeakerBusy())
                w = 10;
            else if (m_conn || !m_spk.empty() || m_in->isOpen())
                w = 50;
            else if (m_out->isOpen() || !m_speakers.empty() || needMic())
                // until the next housekeeping (a wait that ends a hair early
                // must not skip one); needMic: a microphone that did not open
                // is tried again and the device lists stay fresh (meter, test)
                w = (std::max)(int64_t{ 1 }, m_houseAt + kHouseMs - t);
            if (!m_delayed.empty()) {
                const int64_t d = (std::max)(int64_t{ 0 }, m_delayed.begin()->first - t);
                w = w < 0 ? d : (std::min)(w, d);
            }
            return w;
        }

        bool anySpeakerBusy() const
        {
            for (const auto& [sid, sp] : m_speakers) {
                if (!sp->jb.idle() || sp->queuedSpurt)
                    return true;
            }
            return false;
        }

        void tick(const int64_t t)
        {
            releaseDelayed(t);
            pollGlobalKey(t);
            micTick(t);
            captureTick(t);
            playbackTick(t);
            spkTick(t);
            if (t - m_houseAt >= kHouseMs) {
                m_houseAt = t;
                house(t);
            }
        }

        void shutdownAll()
        {
            closeSocket();
            speakersOff();
            m_gate = false;
            closeMic();
            for (auto& [sid, sp] : m_speakers) {
                if (sp->stream >= 0)
                    m_out->closeStream(sp->stream);
            }
            m_speakers.clear();
            m_out->close();
            m_enc.close();
            m_delayed.clear();
        }

        // -- connection ----------------------------------------------------------

        bool connOpen() const { return m_conn && m_conn->open; }

        // voice activation talks in the first room joined (party, guild, room,
        // near): a player who does not want to be heard leaves the room
        bool hasVadRoom() const
        {
            for (const auto& r : m_rooms) {
                if (!r.empty())
                    return true;
            }
            return false;
        }

        bool canSend() const { return connOpen() && m_sid != 0 && !m_deaf && !m_smute; }

        void doConnect(const std::string& url, const std::string& token, const std::string& clientTag,
                       const std::string& build)
        {
            closeSocket();
            endConnection();
            auto c = std::make_unique<Conn>();
            c->url = url;
            c->token = token;
            c->clientTag = clientTag.empty() ? "win" : clientTag;
            c->build = build.substr(0, 40);
            const bool tls = url.rfind("wss://", 0) == 0;
            c->bundle = tls && !m_preferSystem && fileExists(m_opt.caFile);
            m_conn = std::move(c);
            m_seq = 0;
            ++m_n.sockets;
            emit("state", "connecting");
            startSocket();
        }

        void startSocket()
        {
            Conn& c = *m_conn;
            c.gen = ++m_gen;
            c.open = false;
            auto ws = std::make_shared<ix::WebSocket>();
            ws->setUrl(c.url);
            ws->addSubProtocol("mythos-voice.1");
            ws->setPerMessageDeflateOptions(ix::WebSocketPerMessageDeflateOptions(false));
            ws->setPingInterval(15);
            ws->setHandshakeTimeout(10);
            ws->disableAutomaticReconnection(); // Lua owns the backoff
            // the relay refuses any Origin it does not list; a native client
            // sends an empty one (ixwebsocket would make one up otherwise)
            ix::WebSocketHttpHeaders headers;
            headers["Origin"] = "";
            ws->setExtraHeaders(headers);
            if (c.url.rfind("wss://", 0) == 0) {
                ix::SocketTLSOptions tls;
                tls.caFile = c.bundle ? caBundle(m_opt.caFile) : std::string("SYSTEM");
                ws->setTLSOptions(tls);
            }
            const std::shared_ptr<Box> box = m_box;
            const uint32_t gen = c.gen;
            ws->setOnMessageCallback([box, gen](const ix::WebSocketMessagePtr& msg) { onSocketMessage(*box, gen, msg); });
            c.ws = ws;
            ws->start();
        }

        // on ixwebsocket's thread: copy into the inbox, nothing else
        static void onSocketMessage(Box& box, const uint32_t gen, const ix::WebSocketMessagePtr& msg)
        {
            if (!msg)
                return;
            bool wake = true;
            {
                std::lock_guard<std::mutex> lock(box.mutex);
                switch (msg->type) {
                    case ix::WebSocketMessageType::Open: {
                        Inbound& e = box.in.emplace_back();
                        e.kind = Inbound::Kind::Open;
                        e.gen = gen;
                        break;
                    }
                    case ix::WebSocketMessageType::Message: {
                        if (!msg->binary) {
                            Inbound& e = box.in.emplace_back();
                            e.kind = Inbound::Kind::Text;
                            e.gen = gen;
                            e.text = msg->str;
                            break;
                        }
                        const auto* p = reinterpret_cast<const uint8_t*>(msg->str.data());
                        const size_t n = msg->str.size();
                        ++box.binMsgs;
                        box.binBytes += n;
                        const int64_t at = nowMs();
                        const bool ok = voiceproto::parseDown(p, n, [&](const int slot, const bool end, const bool vad,
                                                                        const uint16_t sid, const uint8_t seq,
                                                                        const uint8_t* opus, const size_t len) {
                            if (box.audio >= kInboxAudioMax) {
                                ++box.inboxDrops;
                                return;
                            }
                            Inbound& e = box.in.emplace_back();
                            e.kind = Inbound::Kind::Audio;
                            e.gen = gen;
                            e.sid = sid;
                            e.flags = voiceproto::makeFlags(slot, end, vad);
                            e.seq = seq;
                            e.len = static_cast<uint8_t>(len);
                            std::memcpy(e.data, opus, len);
                            e.at = at;
                            ++box.audio;
                        });
                        if (!ok)
                            ++box.bad;
                        break;
                    }
                    case ix::WebSocketMessageType::Close: {
                        Inbound& e = box.in.emplace_back();
                        e.kind = Inbound::Kind::Closed;
                        e.gen = gen;
                        e.code = msg->closeInfo.code ? msg->closeInfo.code : 1006;
                        e.text = msg->closeInfo.reason.substr(0, 120);
                        break;
                    }
                    case ix::WebSocketMessageType::Error: {
                        Inbound& e = box.in.emplace_back();
                        e.kind = Inbound::Kind::Closed;
                        e.gen = gen;
                        e.code = 1006;
                        e.text = msg->errorInfo.reason.substr(0, 300);
                        e.tlsRetry = msg->errorInfo.http_status == 0 && tlsError(msg->errorInfo.reason);
                        break;
                    }
                    default:
                        wake = false; // ping, pong, fragment
                        break;
                }
            }
            if (wake)
                box.cv.notify_one();
        }

        // a socket we close ourselves reports nothing (a new connect may follow);
        // stopping it joins ixwebsocket's thread, here on the voz thread
        void closeSocket()
        {
            if (!m_conn)
                return;
            std::unique_ptr<Conn> c = std::move(m_conn);
            ++m_gen; // whatever it still says is dropped
            if (c->ws) {
                // its callback (which only holds the inbox) is left in place:
                // ixwebsocket calls it without a lock; the generation drops it
                c->ws->stop(1000, "bye");
                c->ws.reset();
            }
        }

        void endConnection()
        {
            m_sid = 0;
            for (auto& r : m_rooms)
                r.clear();
            m_maxOpus = voiceproto::kMaxOpus;
            m_users.clear(); // sids belong to one relay session; the game sends them again
            m_places.clear();
            m_keyTx = -1;
            speakersOff();
            for (auto& [sid, sp] : m_speakers) {
                if (sp->stream >= 0)
                    m_out->closeStream(sp->stream);
            }
            m_speakers.clear();
            m_delayed.clear();
            if (m_gate) {
                m_gate = false;
                emit("talk", std::string(), -1);
            }
        }

        // end: terminate (the meter goes too); otherwise the settings window
        // may still be open and its meter goes on
        void doDisconnect(const bool end)
        {
            closeSocket();
            endConnection();
            m_test = false;
            if (end)
                m_meter = false;
            if (!m_meter)
                closeMic();
            if (m_out->isOpen())
                closeOutput();
        }

        void doSendControl(const std::string& text)
        {
            if (!connOpen() || text.empty())
                return;
            if (text.find("\"leave\"") != std::string::npos) {
                const auto m = json::parse(text, nullptr, false);
                if (m.is_object() && m.value("t", std::string()) == "leave")
                    forgetRoom(m.value("room", std::string()));
            }
            m_conn->ws->sendText(validUtf8(text) ? text : latin1ToUtf8(text));
            ++m_n.ctlOut;
        }

        void forgetRoom(const std::string& id)
        {
            if (id.empty())
                return;
            for (auto& r : m_rooms) {
                if (r == id)
                    r.clear();
            }
        }

        void onInbound(Inbound& item, const int64_t t)
        {
            if (!m_conn || item.gen != m_conn->gen)
                return; // a socket replaced or closed meanwhile
            switch (item.kind) {
                case Inbound::Kind::Open:
                    onOpen();
                    break;
                case Inbound::Kind::Text:
                    ++m_n.ctlIn;
                    trackRooms(item.text);
                    emit("ctl", std::move(item.text));
                    break;
                case Inbound::Kind::Audio:
                    if (m_inject)
                        inject(item, t);
                    else
                        onAudio(item, t);
                    break;
                case Inbound::Kind::Closed:
                    onClosed(item);
                    break;
            }
        }

        void onOpen()
        {
            Conn& c = *m_conn;
            c.open = true;
            m_tlsUsed = c.url.rfind("wss://", 0) == 0 ? (c.bundle ? "bundle" : "system") : "none";
            // the list that worked after the other failed is tried first from
            // now on; only a success moves it (a handshake that failed for
            // another reason must not leave a list that does not work here)
            if (c.retried)
                m_preferSystem = !c.bundle;
            json hello = { { "t", "hello" }, { "v", 1 }, { "tok", c.token }, { "cl", c.clientTag }, { "b", c.build }, { "a", 1 } };
            c.ws->sendText(hello.dump(-1, ' ', false, json::error_handler_t::replace));
            c.token.assign(c.token.size(), '\0');
            c.token.clear();
            emit("state", "open");
        }

        void onClosed(const Inbound& item)
        {
            Conn& c = *m_conn;
            if (!c.open && item.tlsRetry && !c.retried && c.url.rfind("wss://", 0) == 0) {
                // the other certificate list: the shipped bundle may be stale,
                // or the system's may lack the relay's root (an old Windows)
                const bool canBundle = fileExists(m_opt.caFile);
                if (c.bundle || canBundle) {
                    log(1, "voice: TLS failed (" + item.text + "), trying the " + (c.bundle ? "system's" : "bundled") +
                               " certificate list");
                    c.retried = true;
                    c.bundle = !c.bundle;
                    ++m_n.tlsRetries;
                    if (c.ws) {
                        c.ws->stop();
                        c.ws.reset();
                    }
                    startSocket();
                    return;
                }
            }
            if (!c.open && !item.text.empty())
                log(1, "voice: connection failed: " + item.text);
            const int code = item.code;
            closeSocket();
            emit("state", "closed", code);
            endConnection();
        }

        // the rooms we are in, from the relay's own messages (voice activation
        // needs the slot, and frames for a slot without a room are not sent);
        // every relay message starts {"t":"
        void trackRooms(const std::string& text)
        {
            if (text.size() > 65536 || text.rfind("{\"t\":\"", 0) != 0)
                return;
            const std::string t = text.substr(6, 8);
            if (t.rfind("welcome\"", 0) != 0 && t.rfind("roster\"", 0) != 0 && t.rfind("left\"", 0) != 0 &&
                t.rfind("moved\"", 0) != 0)
                return;
            const auto m = json::parse(text, nullptr, false);
            if (!m.is_object())
                return;
            const std::string type = m.value("t", std::string());
            if (type == "welcome") {
                const auto sid = m.find("sid");
                m_sid = sid != m.end() && sid->is_number_integer() ? sid->get<int>() : 0;
                for (auto& r : m_rooms)
                    r.clear();
                m_maxOpus = voiceproto::kMaxOpus;
                const auto lim = m.find("lim");
                if (lim != m.end() && lim->is_object()) {
                    const auto pl = lim->find("pl");
                    if (pl != lim->end() && pl->is_number()) {
                        const double v = pl->get<double>();
                        if (v >= 1)
                            m_maxOpus = static_cast<size_t>((std::min)(static_cast<double>(voiceproto::kMaxOpus), std::floor(v)));
                    }
                }
            } else if (type == "roster" || type == "moved") {
                const auto slot = m.find("slot");
                if (slot == m.end() || !slot->is_number_integer())
                    return;
                const int k = slot->get<int>();
                const auto room = m.find(type == "roster" ? "room" : "to");
                if (k >= 0 && k < kSlots && room != m.end() && room->is_string())
                    m_rooms[k] = room->get<std::string>();
            } else if (type == "left") {
                forgetRoom(m.value("room", std::string()));
            }
        }

        // -- receiving -----------------------------------------------------------

        // test harness: loss, jitter and stalls on the received frames
        void inject(const Inbound& item, const int64_t t)
        {
            std::uniform_real_distribution<double> unit(0.0, 1.0);
            if (m_opt.lossRate > 0 && unit(m_rng) < m_opt.lossRate) {
                ++m_n.injLost;
                return;
            }
            int64_t at = t;
            if (m_opt.jitterMs > 0) {
                at += static_cast<int64_t>(unit(m_rng) * m_opt.jitterMs);
                ++m_n.injDelayed;
            }
            if (m_opt.stallMs > 0 && m_opt.stallEveryMs > 0) {
                const int64_t phase = t % m_opt.stallEveryMs;
                if (phase < m_opt.stallMs) {
                    at = (std::max)(at, t - phase + m_opt.stallMs);
                    ++m_n.injStalled;
                }
            }
            if (at <= t && m_delayed.empty()) {
                onAudio(item, t);
                return;
            }
            m_delayed.emplace(at, item);
        }

        void releaseDelayed(const int64_t t)
        {
            while (!m_delayed.empty() && m_delayed.begin()->first <= t) {
                const Inbound item = m_delayed.begin()->second;
                m_delayed.erase(m_delayed.begin());
                onAudio(item, t);
            }
        }

        void onAudio(const Inbound& item, const int64_t t)
        {
            const bool end = (item.flags & voiceproto::kEnd) != 0;
            ++m_n.inF;
            m_n.inOpus += item.len;
            if (end)
                ++m_n.inEnd;
            speaking(item.sid, item.len, end, t);
            if (m_deaf) {
                ++m_n.deafDrop;
                return;
            }
            deliver(item.sid, item.flags & voiceproto::kSlotMask, item.seq, end, item.data, item.len, t);
        }

        void deliver(const int sid, const int slot, const uint8_t seq, const bool end, const uint8_t* data,
                     const size_t len, const int64_t t)
        {
            const int samples = voicecodec::packetSamples(data, len);
            if (samples <= 0 || samples > voicecodec::kMaxFrameSamples) {
                ++m_n.decErr;
                return;
            }
            Speaker* sp = speaker(sid, t);
            if (!sp)
                return;
            sp->lastAt = t;
            sp->jb.setLeadMs((samples + 24) / 48); // one frame: OpenAL holds two
            sp->jb.push(seq, end, data, len, samples, t, slot);
            m_outActiveAt = t;
        }

        Speaker* speaker(const int sid, const int64_t t)
        {
            const auto it = m_speakers.find(sid);
            if (it != m_speakers.end())
                return it->second.get();
            if (m_speakers.size() >= kMaxSpeakers) {
                // the least recently heard goes
                int oldest = -1;
                int64_t at = (std::numeric_limits<int64_t>::max)();
                for (const auto& [k, sp] : m_speakers) {
                    if (sp->lastAt < at) {
                        at = sp->lastAt;
                        oldest = k;
                    }
                }
                dropSpeaker(oldest);
            }
            auto sp = std::make_unique<Speaker>();
            if (!sp->dec.open()) {
                ++m_n.decErr;
                return nullptr;
            }
            sp->lastAt = t;
            ++m_n.decNew;
            Speaker* raw = sp.get();
            m_speakers.emplace(sid, std::move(sp));
            return raw;
        }

        void dropSpeaker(const int sid)
        {
            const auto it = m_speakers.find(sid);
            if (it == m_speakers.end())
                return;
            addMix(it->second->jb.stats());
            if (it->second->stream >= 0)
                m_out->closeStream(it->second->stream);
            m_speakers.erase(it);
        }

        void addMix(const JitterBuffer::Stats& s)
        {
            m_mixDone.late += s.late;
            m_mixDone.conceal += s.conceal;
            m_mixDone.trimmed += s.trimmed;
            m_mixDone.played += s.played;
            m_mixDone.spurts += s.spurts;
            m_mixDone.dup += s.dup;
            m_mixDone.resets += s.resets;
            m_mixDone.maxBufferedMs = (std::max)(m_mixDone.maxBufferedMs, s.maxBufferedMs);
        }

        // on: the first frame over 10 B; off: END or 300 ms without frames
        void speaking(const int sid, const size_t len, const bool end, const int64_t t)
        {
            SpeakingEdge& s = m_spk[sid];
            s.last = t;
            if (end) {
                if (s.on) {
                    s.on = false;
                    emit("spk", std::string(), sid, 0);
                }
                return;
            }
            if (!s.on && len > voiceproto::kSpeechMin) {
                s.on = true;
                emit("spk", std::string(), sid, 1);
            }
        }

        void spkTick(const int64_t t)
        {
            for (auto it = m_spk.begin(); it != m_spk.end();) {
                SpeakingEdge& s = it->second;
                if (s.on && t - s.last > kSpkGapMs) {
                    s.on = false;
                    emit("spk", std::string(), it->first, 0);
                }
                if (!s.on && t - s.last > kSpeakerIdleMs)
                    it = m_spk.erase(it);
                else
                    ++it;
            }
        }

        void speakersOff()
        {
            for (const auto& [sid, s] : m_spk) {
                if (s.on)
                    emit("spk", std::string(), sid, 0);
            }
            m_spk.clear();
        }

        // -- playback ------------------------------------------------------------

        float gainOf(const int sid, const int slot) const
        {
            if (m_deaf && sid != kTestSid)
                return 0.0f;
            const auto it = m_users.find(sid);
            const float user = it != m_users.end() ? it->second : 1.0f;
            const float room = slot >= 0 && slot < kSlots ? m_slotGain[slot] : 1.0f;
            return user * room * m_outVol;
        }

        // a near speaker's new place; heard now on slot 3: there in
        // kPlaceRampMs (each playback tick moves it, OpenAL fades each step),
        // else at once (its next slot-3 frame starts there)
        void placeSpeaker(const int sid, const float gain, const float pan, const int64_t t)
        {
            const auto [it, fresh] = m_places.try_emplace(sid);
            Place& pl = it->second;
            if (!fresh && pl.gain == gain && pl.pan == pan)
                return;
            pl.gain = gain;
            pl.pan = pan;
            const auto sp = m_speakers.find(sid);
            if (sp != m_speakers.end() && sp->second->queuedSpurt && sp->second->playSlot == kNearSlot) {
                advancePlace(pl, t); // from where it is heard now
                pl.fromGain = pl.curGain;
                pl.fromPan = pl.curPan;
                pl.rampAt = t;
                pl.ramp = true;
            } else {
                pl.curGain = gain;
                pl.curPan = pan;
                pl.ramp = false;
            }
        }

        static void advancePlace(Place& pl, const int64_t t)
        {
            if (!pl.ramp)
                return;
            const float f = std::clamp(static_cast<float>(t - pl.rampAt) / static_cast<float>(kPlaceRampMs), 0.0f, 1.0f);
            if (f >= 1.0f) {
                pl.curGain = pl.gain;
                pl.curPan = pl.pan;
                pl.ramp = false;
                return;
            }
            pl.curGain = pl.fromGain + (pl.gain - pl.fromGain) * f;
            pl.curPan = pl.fromPan + (pl.pan - pl.fromPan) * f;
        }

        // the gain and the place of what the stream plays now, a frame of
        // `slot`: centred at the listener, except slot 3 of a speaker with a
        // place. Base gains above 1 are on the samples (queue time).
        void hear(const Speaker& sp, const int sid, const int slot, const int64_t t)
        {
            const float g = (std::min)(1.0f, gainOf(sid, slot));
            if (slot == kNearSlot && !m_places.empty()) {
                const auto it = m_places.find(sid);
                if (it != m_places.end()) {
                    advancePlace(it->second, t);
                    m_out->setGain(sp.stream, g * it->second.curGain);
                    m_out->setPan(sp.stream, true, it->second.curPan);
                    return;
                }
            }
            m_out->setGain(sp.stream, g);
            m_out->setPan(sp.stream, false, 0.0f);
        }

        // the buffers OpenAL finished playing (pending() left `pend`) leave
        // the front of the stream's list; the first one left is heard now
        static void played(Speaker& sp, const int pend)
        {
            const int done = sp.queuedN - (std::max)(0, pend);
            if (done > 0) {
                for (int i = done; i < sp.queuedN; ++i)
                    sp.queued[i - done] = sp.queued[i];
                sp.queuedN -= done;
            }
            if (sp.queuedN > 0)
                sp.playSlot = sp.queued[0];
        }

        bool openOutput(const int64_t t)
        {
            if (m_out->isOpen())
                return true;
            if (t < m_outRetryAt)
                return false;
            ++m_n.outOpens;
            const int64_t t0 = nowMs();
            const bool opened = m_out->open(m_outDev);
            noteDeviceCall("opening the output device", nowMs() - t0, m_n.outOpenMaxMs);
            if (!opened) {
                m_outRetryAt = t + kOutRetryMs;
                log(1, "voice: the output device could not be opened");
                return false;
            }
            m_outUnresolved = !m_outDev.empty() && m_out->openedName() != m_outDev;
            m_outActiveAt = t;
            return true;
        }

        void closeOutput()
        {
            for (auto& [sid, sp] : m_speakers) {
                sp->stream = -1; // their sources go with the device
                sp->queuedSpurt = false;
                sp->queuedN = 0;
            }
            m_out->close();
        }

        // without a device the frames still have to leave the buffers
        static void discard(Speaker& sp, const int64_t t)
        {
            for (int i = 0; i < 16; ++i) {
                const auto r = sp.jb.pull(t);
                if (r.kind == JitterBuffer::Kind::Idle || r.kind == JitterBuffer::Kind::Silence)
                    break;
            }
            sp.queuedSpurt = false;
            sp.queuedN = 0;
        }

        void playbackTick(const int64_t t)
        {
            if (m_speakers.empty())
                return;
            if (!anySpeakerBusy())
                return;
            if (!openOutput(t)) {
                for (auto& [sid, sp] : m_speakers)
                    discard(*sp, t);
                return;
            }
            int16_t* pcm = m_scratch.data();
            for (auto& [sid, spp] : m_speakers) {
                Speaker& sp = *spp;
                if (sp.jb.idle() && !sp.queuedSpurt)
                    continue;
                sp.jb.maintain(t); // the 400 ms cap also while OpenAL is full
                if (sp.stream < 0) {
                    sp.stream = m_out->openStream();
                    sp.queuedN = 0;
                    if (sp.stream < 0) {
                        discard(sp, t);
                        continue;
                    }
                }
                int pend = m_out->pending(sp.stream);
                played(sp, pend);
                if (pend == 0 && sp.queuedSpurt) {
                    if (sp.jb.playing())
                        ++m_n.underruns;
                    else if (sp.jb.idle())
                        sp.queuedSpurt = false; // the spurt played out
                }
                if (sp.queuedN > 0)
                    hear(sp, sid, sp.playSlot, t);
                while (pend < kLeadBuffers && m_out->canQueue(sp.stream)) {
                    const auto r = sp.jb.pull(t);
                    int n = 0;
                    if (r.kind == JitterBuffer::Kind::Frame) {
                        n = sp.dec.decode(r.data, r.size, pcm, voicecodec::kMaxFrameSamples);
                        if (n > 0) {
                            ++m_n.decOut;
                        } else {
                            ++m_n.decErr;
                            n = sp.dec.conceal(pcm, r.samples);
                        }
                    } else if (r.kind == JitterBuffer::Kind::Conceal) {
                        n = sp.dec.conceal(pcm, r.samples);
                        ++m_n.conceal;
                    } else {
                        break;
                    }
                    if (n <= 0)
                        break;
                    const float boost = gainOf(sid, r.slot); // above 1: on the samples, saturating
                    if (boost > 1.0f) {
                        for (int i = 0; i < n; ++i)
                            pcm[i] = saturate(pcm[i] * boost);
                    }
                    if (sp.queuedN == 0) {
                        // nothing queued: this one plays at once
                        sp.playSlot = r.slot;
                        hear(sp, sid, r.slot, t);
                    }
                    if (!m_out->queue(sp.stream, pcm, n))
                        break;
                    if (sp.queuedN < kMaxQueued)
                        sp.queued[sp.queuedN++] = static_cast<uint8_t>(r.slot);
                    sp.queuedSpurt = true;
                    ++pend;
                    m_outActiveAt = t;
                }
            }
        }

        // -- capture -------------------------------------------------------------

        int effTx() const
        {
            if (m_deaf || m_smute)
                return -1;
            if (m_keyTx >= 0)
                return m_keyTx;
            if (m_globalHeld && !m_globalBlocked && connOpen())
                return vadSlot(); // the background key talks where the talk key does
            return -1;
        }

        // voice activation listens only while it could send: connected, in a
        // room, not self-muted (in no room every spurt would be dropped)
        bool vadArmed() const { return m_vad && !m_smute && connOpen() && hasVadRoom(); }

        bool needMic() const { return effTx() >= 0 || m_test || m_meter || vadArmed(); }

        bool capturing() const { return m_gate || needMic(); }

        // voice activation talks in the party room, else the first room
        // joined (guild, public, near): the same place as the one talk key
        int vadSlot() const
        {
            for (int i = 0; i < kSlots; ++i) {
                if (!m_rooms[i].empty())
                    return i;
            }
            return 0;
        }

        void pollGlobalKey(const int64_t t)
        {
            if (!m_globalVk || !connOpen()) {
                m_globalHeld = false;
                m_globalBlocked = false;
                return;
            }
            const bool down = m_opt.keyHeld ? m_opt.keyHeld(m_globalVk) : voiceGlobalKeyHeld(m_globalVk);
            if (down && !m_globalHeld) {
                m_globalHeld = true;
                m_globalSince = t;
                // as the browser's mouse button: a press with no party room,
                // or while sending is impossible, is ignored until released
                m_globalBlocked = m_rooms[0].empty() || !canSend();
            } else if (!down && m_globalHeld) {
                m_globalHeld = false;
                m_globalBlocked = false;
            }
            if (m_globalHeld && !m_globalBlocked && t - m_globalSince > kGlobalTxMaxMs)
                m_globalBlocked = true;
        }

        void micTick(const int64_t t)
        {
            if (m_in->isOpen() && m_in->lost()) {
                closeMic();
                m_mic = MicState::NoDevice;
                m_micFailAt = t;
                emit("mic", "nodevice"); // unplugged
            }
            if (!needMic()) {
                if (m_in->isOpen() && (t - m_micUsedAt > kMicIdleMs || (m_vad && m_smute)))
                    closeMic();
                return;
            }
            m_micUsedAt = t;
            if (m_in->isOpen()) {
                const bool move = m_micCheck && m_micUnresolved && contains(m_seenIn, m_inDev);
                m_micCheck = false;
                if (m_micReopen || move) {
                    // another device chosen, or the saved one is back
                    m_micReopen = false;
                    ++m_n.micMoves;
                    closeMic();
                    openMic(t);
                }
                return;
            }
            m_micReopen = false;
            if (m_mic == MicState::NoDevice || m_mic == MicState::Denied) {
                const int64_t wait = effTx() >= 0 || m_test ? kMicRetryPressMs : kMicRetryMs;
                if (t - m_micFailAt < wait)
                    return;
            }
            openMic(t);
        }

        void openMic(const int64_t t)
        {
            const int64_t t0 = nowMs();
            const bool opened = m_in->open(m_inDev, kRate);
            noteDeviceCall("opening the microphone", nowMs() - t0, m_n.micOpenMaxMs);
            if (opened) {
                m_mic = MicState::On;
                m_micUnresolved = !m_inDev.empty() && m_in->openedName() != m_inDev;
                m_fill = 0;
                m_hasPrev = false;
                m_vadOn = false;
                m_levelSum = 0;
                m_levelN = 0;
                emit("mic", "ok");
                return;
            }
            // devices listed but none opens: on Windows, the privacy setting
            // (or another program holding it); none listed: no microphone
            const bool any = !m_in->devices().empty();
            const MicState s = any ? MicState::Denied : MicState::NoDevice;
            if (s != m_mic)
                emit("mic", any ? "denied" : "nodevice");
            m_mic = s;
            m_micFailAt = t;
        }

        void closeMic()
        {
            if (m_in->isOpen())
                m_in->close();
            if (m_mic == MicState::On)
                m_mic = MicState::Off;
            m_micUnresolved = false;
            m_fill = 0;
            m_hasPrev = false;
            m_vadOn = false;
            m_enc.close();
            if (m_gate) {
                m_gate = false;
                emit("talk", std::string(), -1);
            }
        }

        void captureTick(const int64_t t)
        {
            if (!m_in->isOpen())
                return;
            int avail = m_in->available();
            if (!capturing()) {
                // open but unused (push-to-talk released): old audio goes
                while (avail > 0) {
                    const int n = m_in->read(m_scratch.data(), (std::min)(avail, static_cast<int>(m_scratch.size())));
                    if (n <= 0)
                        break;
                    avail -= n;
                }
                m_fill = 0;
                m_hasPrev = false;
                return;
            }
            for (int guard = 0; avail > 0 && guard < 64; ++guard) {
                const int frame = static_cast<int>(m_frame.size()); // onFrame may change it
                const int want = (std::min)(avail, frame - m_fill);
                const int n = m_in->read(m_frame.data() + m_fill, want);
                if (n <= 0)
                    break;
                processInput(m_frame.data() + m_fill, n);
                m_fill += n;
                avail -= n;
                if (m_fill >= frame) {
                    m_fill = 0;
                    onFrame(t);
                }
            }
        }

        // gain (saturating) and the level meter
        void processInput(int16_t* pcm, const int n)
        {
            if (m_inGain != 1.0f) {
                for (int i = 0; i < n; ++i)
                    pcm[i] = saturate(pcm[i] * m_inGain);
            }
            if (!m_meter)
                return;
            for (int i = 0; i < n; ++i) {
                const double x = pcm[i] / 32768.0;
                m_levelSum += x * x;
                if (++m_levelN >= kLevelWindow) {
                    const int db = static_cast<int>(std::lround((std::max)(-100.0, dbOf(m_levelSum, m_levelN))));
                    emit("level", std::string(), db);
                    m_levelSum = 0;
                    m_levelN = 0;
                }
            }
        }

        // one frame: the push-to-talk / voice-activation gate (the browser's
        // mv-capture onFrame), then Opus
        void onFrame(const int64_t t)
        {
            const int n = static_cast<int>(m_frame.size());
            double sum = 0;
            for (int i = 0; i < n; ++i) {
                const double x = m_frame[i] / 32768.0;
                sum += x * x;
            }
            const double db = dbOf(sum, n);
            const int hang = (std::max)(1, static_cast<int>(std::lround(300.0 * kRate / n / 1000.0)));
            const bool muted = m_smute || m_deaf;
            if (m_vad && connOpen() && hasVadRoom() && !muted) {
                if (db >= m_vadDb) {
                    m_vadOn = true;
                    m_hang = hang;
                } else if (m_vadOn) {
                    if (db >= m_vadDb - 6.0)
                        m_hang = hang;
                    else if (--m_hang <= 0)
                        m_vadOn = false;
                }
            } else {
                m_vadOn = false;
            }
            const int tx = effTx();
            const bool want = !muted && (tx >= 0 || m_vadOn);
            const int slot = tx >= 0 ? tx : vadSlot();
            bool sent = false;
            if (want && !m_gate) {
                m_gate = true;
                m_gateSlot = slot;
                m_gateVad = tx < 0;
                emit("talk", std::string(), slot);
                if (m_gateVad && m_hasPrev) {
                    encodeFrame(m_prev.data(), true, false, slot, true, true, t); // pre-roll
                    encodeFrame(m_frame.data(), true, false, slot, true, false, t);
                } else {
                    encodeFrame(m_frame.data(), true, false, slot, m_gateVad, true, t);
                }
                sent = true;
            } else if (m_gate) {
                const bool closing = !want || slot != m_gateSlot;
                encodeFrame(m_frame.data(), true, closing, m_gateSlot, m_gateVad, false, t);
                sent = true;
                if (closing) {
                    m_gate = false;
                    emit("talk", std::string(), -1);
                }
            } else if (m_test) {
                // no spurt on the network: the test follows a preset change at once
                encodeFrame(m_frame.data(), false, false, kTestSlot, false, true, t);
                sent = true;
            }
            // a new frame size (preset) waits for the end of the spurt
            const int size = voicecodec::preset(m_preset).frameSamples;
            if (!m_gate && size != n) {
                m_frame.assign(size, 0);
                m_prev.assign(size, 0);
                m_hasPrev = false;
                m_fill = 0;
                return;
            }
            if (sent) {
                m_hasPrev = false;
            } else {
                m_prev.swap(m_frame);
                m_hasPrev = true;
            }
        }

        // the preset for frames of n samples. Inside a spurt the open encoder
        // stays (a new one breaks the codec state the listeners decode with):
        // a new preset starts with the next spurt, as in the browser. Else the
        // player's, else one with that size.
        int presetFor(const int n, const bool first) const
        {
            if (!first && m_enc.isOpen() && m_enc.frameSamples() == n)
                return m_enc.presetIndex();
            if (voicecodec::preset(m_preset).frameSamples == n)
                return m_preset;
            for (const int p : { 0, 2, 1 }) {
                if (voicecodec::preset(p).frameSamples == n)
                    return p;
            }
            return 0;
        }

        void encodeFrame(const int16_t* pcm, const bool netWanted, const bool end, const int slot, const bool vad,
                         const bool first, const int64_t t)
        {
            bool net = netWanted && canSend();
            if (net && (slot < 0 || slot >= kSlots || m_rooms[slot].empty())) {
                net = false; // no room on that slot: the relay would drop it
                ++m_n.upNoRoom;
            }
            const bool test = m_test;
            if (!net && !test)
                return;
            const int n = static_cast<int>(m_frame.size());
            const int p = presetFor(n, first);
            if (!m_enc.isOpen() || m_enc.frameSamples() != n || m_enc.presetIndex() != p) {
                if (t < m_encCoolUntil) {
                    ++m_n.upDrop;
                    return;
                }
                ++m_n.encNew;
                if (!m_enc.open(p)) {
                    ++m_n.encErr;
                    ++m_n.upDrop;
                    m_encCoolUntil = t + kEncCoolMs;
                    if (!m_encFailing) {
                        m_encFailing = true;
                        emit("mic", "encoder");
                    }
                    return;
                }
            }
            uint8_t packet[voiceproto::kUpHeader + voiceproto::kMaxOpus];
            uint8_t* opus = packet + voiceproto::kUpHeader;
            const int len = m_enc.encode(pcm, opus, static_cast<int>(voiceproto::kMaxOpus));
            if (len <= 0) {
                ++m_n.encErr;
                ++m_n.upBig; // OPUS_BUFFER_TOO_SMALL, or an encoder error
                return;
            }
            ++m_n.encOut;
            m_encFailing = false;
            if (net) {
                if (static_cast<size_t>(len) > m_maxOpus) {
                    ++m_n.upBig; // over the relay's limit: it would count it as abuse
                } else if (m_conn->ws->bufferedAmount() > kSendBacklog) {
                    ++m_n.upDrop; // the socket is stuck: late audio is worthless
                } else {
                    const size_t size = voiceproto::packUp(packet, slot, end, vad, m_seq, opus, static_cast<size_t>(len));
                    if (size > 0) {
                        m_conn->ws->sendBinary(ix::IXWebSocketSendData(reinterpret_cast<const char*>(packet), size));
                        m_seq = static_cast<uint8_t>(m_seq + 1);
                        ++m_n.upF;
                        m_n.upB += size;
                    }
                }
            }
            if (test) {
                m_testSeq = static_cast<uint8_t>(m_testSeq + 1);
                deliver(kTestSid, kTestSlot, m_testSeq, end, opus, static_cast<size_t>(len), t);
            }
        }

        // -- housekeeping --------------------------------------------------------

        void house(const int64_t t)
        {
            // speakers silent for 10 s are forgotten (the decoder goes too)
            std::vector<int> idle;
            for (const auto& [sid, sp] : m_speakers) {
                if (sp->jb.idle() && !sp->queuedSpurt && t - sp->lastAt > kSpeakerIdleMs)
                    idle.push_back(sid);
            }
            for (const int sid : idle)
                dropSpeaker(sid);

            if (m_out->isOpen()) {
                const bool idleOut = !anySpeakerBusy() && !m_test && t - m_outActiveAt > kOutIdleCloseMs;
                const bool move = m_outCheck && m_outUnresolved && contains(m_seenOut, m_outDev);
                m_outCheck = false;
                if (m_out->lost() || m_outReopen || move || idleOut) {
                    // unplugged, another device chosen, the saved one is back,
                    // or nothing played for a while: opened again when needed
                    m_outReopen = false;
                    closeOutput();
                }
            } else {
                m_outReopen = false;
            }

            if (t - m_devicesAt >= kDevicePollMs && (m_conn || m_in->isOpen() || m_out->isOpen() || needMic())) {
                m_devicesAt = t;
                // a microphone that appeared is tried at once, not on the next tick
                if (refreshDevices(t) && needMic() && !m_in->isOpen())
                    micTick(t);
            }
        }

        // true when the lists changed
        bool refreshDevices(const int64_t t)
        {
            const int64_t t0 = nowMs();
            auto ins = m_in->devices();
            auto outs = m_out->devices();
            noteDeviceCall("listing the devices", nowMs() - t0, m_n.listMaxMs);
            {
                std::lock_guard<std::mutex> lock(m_devMutex);
                m_inList = ins;
                m_outList = outs;
                m_listed = true;
                m_listedAt = t;
            }
            if (m_devicesKnown && ins == m_seenIn && outs == m_seenOut)
                return false;
            m_devicesKnown = true;
            m_seenIn = ins;
            m_seenOut = outs;
            m_micCheck = true;
            m_outCheck = true;
            if (m_mic == MicState::NoDevice || m_mic == MicState::Denied)
                m_micFailAt = 0; // a microphone may be back: the next need tries at once
            json lists = { { "i", ins }, { "o", outs } };
            emit("devices", lists.dump(-1, ' ', false, json::error_handler_t::replace));
            return true;
        }

        // device calls run on the voz thread: one that blocks (WASAPI, a
        // Bluetooth headset) stalls capture and playback meanwhile, so each is
        // timed; the stats show the worst, and a slow one is logged
        void noteDeviceCall(const char* what, const int64_t ms, int64_t& maxMs)
        {
            if (ms > maxMs) {
                maxMs = ms;
                if (ms >= kSlowDeviceLogMs)
                    log(1, std::string("voice: ") + what + " took " + std::to_string(ms) + " ms");
            }
            if (ms >= kSlowDeviceMs)
                ++m_n.devSlow;
        }

        json snapshot()
        {
            uint64_t binMsgs = 0, binBytes = 0, bad = 0, inboxDrops = 0;
            {
                std::lock_guard<std::mutex> lock(m_box->mutex);
                binMsgs = m_box->binMsgs;
                binBytes = m_box->binBytes;
                bad = m_box->bad;
                inboxDrops = m_box->inboxDrops;
            }
            JitterBuffer::Stats mix = m_mixDone;
            json targets = json::object();
            json speakingList = json::array();
            for (const auto& [sid, sp] : m_speakers) {
                const auto& s = sp->jb.stats();
                mix.late += s.late;
                mix.conceal += s.conceal;
                mix.trimmed += s.trimmed;
                mix.played += s.played;
                mix.spurts += s.spurts;
                mix.dup += s.dup;
                mix.resets += s.resets;
                mix.maxBufferedMs = (std::max)(mix.maxBufferedMs, s.maxBufferedMs);
                targets[std::to_string(sid)] = sp->jb.targetMs();
            }
            for (const auto& [sid, s] : m_spk) {
                if (s.on)
                    speakingList.push_back(sid);
            }
            json rooms = json::array();
            for (const auto& r : m_rooms) {
                if (r.empty())
                    rooms.push_back(nullptr);
                else
                    rooms.push_back(r);
            }
            const auto& n = m_n;
            json s = {
                { "v", 1 },
                { "engine", "native" },
                { "sup", m_supported },
                { "state", m_conn ? (m_conn->open ? "open" : "connecting") : "idle" },
                { "sid", m_sid },
                { "rooms", rooms },
                { "mic", micName(m_mic) },
                { "micDev", m_in->isOpen() ? m_in->openedName() : std::string() },
                { "micMoves", n.micMoves },
                { "tx", effTx() },
                { "keyTx", m_keyTx },
                { "globalTx", m_globalHeld && !m_globalBlocked },
                { "mouseTx", false },
                { "vad", m_vad },
                { "gate", m_gate },
                { "deaf", m_deaf },
                { "smute", m_smute },
                { "preset", m_preset },
                { "up", { { "f", n.upF }, { "b", n.upB }, { "drop", n.upDrop }, { "big", n.upBig }, { "noRoom", n.upNoRoom },
                          { "max", m_maxOpus }, { "enc", n.encOut }, { "encErr", n.encErr }, { "encNew", n.encNew },
                          { "presets", { 1, 1, 1 } } } },
                { "down", { { "m", binMsgs }, { "b", binBytes }, { "f", n.inF }, { "opus", n.inOpus }, { "end", n.inEnd },
                            { "deaf", n.deafDrop }, { "dec", n.decOut }, { "decErr", n.decErr }, { "decNew", n.decNew },
                            { "bad", bad }, { "inboxDrop", inboxDrops } } },
                { "ctl", { { "i", n.ctlIn }, { "o", n.ctlOut } } },
                { "sockets", n.sockets },
                { "tls", m_tlsUsed },
                { "tlsRetries", n.tlsRetries },
                { "decoders", m_speakers.size() },
                { "slots", { m_slotGain[0], m_slotGain[1], m_slotGain[2], m_slotGain[3] } },
                { "spatial", m_places.size() },
                { "speaking", speakingList },
                { "mix", { { "late", mix.late }, { "conceal", mix.conceal }, { "trimmed", mix.trimmed }, { "played", mix.played },
                           { "spurts", mix.spurts }, { "dup", mix.dup }, { "resets", mix.resets }, { "speakers", m_speakers.size() },
                           { "targets", targets }, { "maxBuffered", mix.maxBufferedMs }, { "underruns", n.underruns } } },
                { "out", { { "open", m_out->isOpen() }, { "dev", m_out->isOpen() ? m_out->openedName() : std::string() },
                           { "opens", n.outOpens } } },
                { "dev", { { "micOpenMax", n.micOpenMaxMs }, { "outOpenMax", n.outOpenMaxMs }, { "listMax", n.listMaxMs },
                           { "slow", n.devSlow } } },
                { "errors", m_errors },
                { "lastError", m_lastError },
            };
            if (m_inject)
                s["inject"] = { { "lost", n.injLost }, { "delayed", n.injDelayed }, { "stalled", n.injStalled } };
            return s;
        }

        // -- members -------------------------------------------------------------

        Sink m_sink;
        NativeVoiceOptions m_opt;
        std::shared_ptr<Box> m_box;
        std::thread m_thread;
        bool m_terminated = false;
        bool m_supported = false;
        Ui m_ui;

        std::mutex m_devMutex; // the lists below, read by the caller's thread
        bool m_listed = false;
        int64_t m_listedAt = 0;
        std::vector<std::string> m_inList;
        std::vector<std::string> m_outList;

        // voz thread (or the caller's before that thread exists)
        std::unique_ptr<AudioInput> m_in;
        std::unique_ptr<AudioOutput> m_out;
        int m_keyTx = -1;
        bool m_vad = false;
        float m_vadDb = -45.0f;
        int m_preset = 0;
        std::string m_inDev;
        std::string m_outDev;
        float m_inGain = 1.0f;
        float m_outVol = 1.0f;
        std::map<int, float> m_users;
        std::map<int, Place> m_places; // near speakers' places (setUserSpatial)
        float m_slotGain[kSlots] = { 1.0f, 1.0f, 1.0f, 1.0f };
        bool m_deaf = false;
        bool m_smute = false;
        bool m_meter = false;
        bool m_test = false;
        int m_globalVk = 0;
        bool m_globalHeld = false;
        bool m_globalBlocked = false;
        int64_t m_globalSince = 0;

        std::unique_ptr<Conn> m_conn;
        uint32_t m_gen = 0;
        bool m_preferSystem = false;
        std::string m_tlsUsed;
        int m_sid = 0;
        std::string m_rooms[kSlots]; // party, guild, public, near
        size_t m_maxOpus = voiceproto::kMaxOpus;
        uint8_t m_seq = 0;

        MicState m_mic = MicState::Off;
        int64_t m_micFailAt = 0;
        int64_t m_micUsedAt = 0;
        bool m_micUnresolved = false;
        bool m_micReopen = false;
        std::vector<int16_t> m_frame;
        std::vector<int16_t> m_prev;
        std::vector<int16_t> m_scratch;
        int m_fill = 0;
        bool m_hasPrev = false;
        bool m_gate = false;
        int m_gateSlot = 0;
        bool m_gateVad = false;
        bool m_vadOn = false;
        int m_hang = 0;
        double m_levelSum = 0;
        int m_levelN = 0;
        OpusEnc m_enc;
        int64_t m_encCoolUntil = 0;
        bool m_encFailing = false;
        uint8_t m_testSeq = 0;

        std::map<int, std::unique_ptr<Speaker>> m_speakers;
        std::map<int, SpeakingEdge> m_spk;
        JitterBuffer::Stats m_mixDone;
        int64_t m_outRetryAt = 0;
        int64_t m_outActiveAt = 0;
        bool m_outUnresolved = false;
        bool m_outReopen = false;

        int64_t m_houseAt = 0;
        int64_t m_devicesAt = 0;
        bool m_devicesKnown = false;
        std::vector<std::string> m_seenIn; // the voz thread's copies
        std::vector<std::string> m_seenOut;
        bool m_micCheck = false; // the lists changed: a saved device may be back
        bool m_outCheck = false;

        bool m_inject = false;
        std::mt19937 m_rng;
        std::multimap<int64_t, Inbound> m_delayed;

        Counters m_n;
        uint32_t m_errors = 0;
        std::string m_lastError;
    };
}

std::unique_ptr<VoiceEngine> createNativeVoiceEngine(VoiceEngine::Sink sink, NativeVoiceOptions options)
{
    return std::make_unique<NativeVoiceEngine>(std::move(sink), std::move(options));
}

#ifndef VOICE_STANDALONE

#include <framework/core/logger.h>
#include <framework/core/resourcemanager.h>

// g_voice's engine in the desktop client
std::unique_ptr<VoiceEngine> createVoiceEngine(VoiceEngine::Sink sink)
{
    NativeVoiceOptions options;
    options.caFile = g_resources.getWorkDir() + "cacert.pem"; // shipped next to the client
    options.log = [](const int level, const std::string& text) {
        // g_logger hands a line from another thread to the game thread
        if (level >= 2)
            g_logger.error(text);
        else if (level == 1)
            g_logger.warning(text);
        else
            g_logger.info(text);
    };
    return createNativeVoiceEngine(std::move(sink), std::move(options));
}

#endif // VOICE_STANDALONE

// The global push-to-talk key, the only part of the voice code that needs
// <windows.h> (included last, so its macros reach nothing above).
#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

bool voiceGlobalKeyHeld(const int virtualKey)
{
    if (virtualKey <= 0 || virtualKey >= 256)
        return false;
    if ((GetAsyncKeyState(virtualKey) & 0x8000) == 0)
        return false;
    // the client's own window has the focus: the in-game key handles it (and
    // keeps the chat mode: a letter typed in the chat does not talk)
    const HWND foreground = GetForegroundWindow();
    DWORD pid = 0;
    if (foreground)
        GetWindowThreadProcessId(foreground, &pid);
    if (pid == GetCurrentProcessId())
        return false;
    // another game client has the focus (a second character): its own key
    // handles it, or the player would talk from both
    wchar_t cls[64] = {};
    if (foreground && GetClassNameW(foreground, cls, 64) > 0 && lstrcmpW(cls, L"BASED_ON_TIBIA_GAME_ENGINE") == 0)
        return false;
    return true;
}
#else
bool voiceGlobalKeyHeld(int)
{
    return false;
}
#endif
