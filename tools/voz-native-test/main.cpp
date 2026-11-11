// Mythos Voz: Linux harness for the native voice engine
// (src/framework/voice, built with -DVOICE_STANDALONE).
//
//   voz-native-test --unit
//       protocol framing, jitter buffer (reorder, gap -> concealment, the
//       400 ms cap, reset per spurt, u8 seq wrap, ...), Opus round trip
//   voz-native-test --url ws://127.0.0.1:7391/voz --tok TOKEN --room p:1:1
//                   [--send in.wav [--loop] [--vad [--vad-db -40]] [--slot 0] [--preset 0]]
//                   [--recv out.wav [--wav-out]] [--loss 0.05] [--jitter 60]
//                   [--stall 300 --stall-every 2000] [--seed 1] [--dur 12]
//                   [--terminate-at 5] [--stats-out file.json] [--quiet]
//       --send: a WAV file replaces the microphone (played in real time from
//       the moment the engine opens it); push-to-talk is held on --slot for
//       the whole run, or --vad uses voice activation.
//       --recv: what is heard goes to out.wav. Without --wav-out the real
//       OpenAL playback runs: run it with ALSOFT_DRIVERS=wave and an
//       ALSOFT_CONF whose [wave] file= is out.wav. --wav-out puts a
//       time-driven WAV writer in place of OpenAL.
//       --loss/--jitter/--stall: injected on the engine's inbox side.
//       --terminate-at: terminate() at that second, timed (talking and
//       receiving at once is the shutdown test).
//   voz-native-test --local-test --send in.wav --recv out.wav [--wav-out] [--meter] [--dur 6]
//       the "Testar microfone" path: no relay; the microphone plays back
//       through the codec and the jitter buffer; --meter counts 'level'
//   voz-native-test --meter-only [--send in.wav] [--meter-off-at 1] [--dur 8]
//       only the settings window's level meter: no relay, no test
//   --late-mic 1.5 (any mode): no microphone is listed and none opens until
//       1.5 s, then "Headset" appears (a headset plugged in later); the
//       summary has micOkAtMs, devicesAtMs (the first 'devices' event that
//       lists it) and inputsAtEnd (getInputDevices() from this thread)
//   --preset-at 2,2 (any mode): setPreset(2) at 2 s; the summary's timeline
//       has up.f, up.b and up.encNew once a second
//   --slow-open 150 (with --send or --late-mic): the microphone's open()
//       blocks 150 ms (stats dev.micOpenMax, dev.slow and a log line)
//   voz-native-test --compare ref.wav out.wav [--min-db -35]
//       RMS envelope (100 ms windows) of out.wav against ref.wav, at the
//       best lag: JSON with the differences in dB
//   voz-native-test --openal-check
//       OpenAL Soft: devices, a playback device of our own with a
//       thread-local context, 1 s of tone through a stream (wave backend)
//
// Every line on stdout is one JSON object.

#include "audioio.h"
#include "jitterbuffer.h"
#include "voicecodec.h"
#include "voiceengine_native.h"
#include "voiceprotocol.h"
#include "wavio.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <fstream>
#include <iostream>
#include <map>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include <AL/al.h>
#include <AL/alc.h>
#include <nlohmann/json.hpp>
#include <unistd.h>

using json = nlohmann::json;

namespace
{
    int64_t nowUs()
    {
        using namespace std::chrono;
        return duration_cast<microseconds>(steady_clock::now().time_since_epoch()).count();
    }

    int64_t nowMs() { return nowUs() / 1000; }

    void out(const json& j)
    {
        static std::mutex m;
        std::lock_guard<std::mutex> lock(m);
        std::cout << j.dump(-1, ' ', false, json::error_handler_t::replace) << std::endl;
    }

    // ---------------------------------------------------------------------
    // test devices

    // a WAV file as the microphone, in real time from open(); silence after
    // its end (or again from the start with loop)
    class WavInput final : public AudioInput
    {
    public:
        // presentAtUs > 0: no device is listed and open() fails until then
        // (a headset plugged in later); afterwards it is listed as "Headset"
        // openDelayMs: open() blocks that long (a slow WASAPI or Bluetooth device)
        WavInput(std::vector<int16_t> pcm, const bool loop, const int64_t presentAtUs = 0, const int openDelayMs = 0)
            : m_pcm(std::move(pcm)), m_loop(loop), m_presentAtUs(presentAtUs), m_openDelayMs(openDelayMs)
        {}

        bool open(const std::string&, int) override
        {
            ++m_tries;
            if (m_openDelayMs > 0)
                std::this_thread::sleep_for(std::chrono::milliseconds(m_openDelayMs));
            if (!present())
                return false;
            m_open = true;
            m_t0 = nowUs();
            m_consumed = 0;
            ++m_opens;
            return true;
        }
        void close() override { m_open = false; }
        bool isOpen() const override { return m_open; }
        std::string openedName() const override { return std::string(); }
        bool lost() override { return false; }
        int available() override
        {
            if (!m_open)
                return 0;
            const int64_t due = (nowUs() - m_t0) * 48 / 1000;
            return static_cast<int>(std::max<int64_t>(0, due - m_consumed));
        }
        int read(int16_t* outPcm, const int samples) override
        {
            const int n = std::min(samples, available());
            for (int i = 0; i < n; ++i) {
                const int64_t k = m_consumed + i;
                if (m_pcm.empty())
                    outPcm[i] = 0;
                else if (m_loop)
                    outPcm[i] = m_pcm[static_cast<size_t>(k % static_cast<int64_t>(m_pcm.size()))];
                else
                    outPcm[i] = k < static_cast<int64_t>(m_pcm.size()) ? m_pcm[static_cast<size_t>(k)] : 0;
            }
            m_consumed += n;
            return n;
        }
        // may be called from any thread (audioio.h): reads only the clock
        std::vector<std::string> devices() override
        {
            if (!present())
                return {};
            return { m_presentAtUs > 0 ? "Headset" : "wav" };
        }
        int opens() const { return m_opens; }
        int tries() const { return m_tries; }

    private:
        bool present() const { return m_presentAtUs <= 0 || nowUs() >= m_presentAtUs; }

        std::vector<int16_t> m_pcm;
        bool m_loop;
        int64_t m_presentAtUs;
        int m_openDelayMs;
        bool m_open = false;
        int64_t m_t0 = 0;
        int64_t m_consumed = 0;
        int m_opens = 0;
        int m_tries = 0;
    };

    class NoInput final : public AudioInput
    {
    public:
        bool open(const std::string&, int) override { return false; }
        void close() override {}
        bool isOpen() const override { return false; }
        std::string openedName() const override { return std::string(); }
        bool lost() override { return false; }
        int available() override { return 0; }
        int read(int16_t*, int) override { return 0; }
        std::vector<std::string> devices() override { return {}; }
    };

    // a speaker that plays in real time onto one timeline, written as a WAV
    // file at the end (path "" discards)
    class WavOutput final : public AudioOutput
    {
    public:
        explicit WavOutput(std::string path) : m_path(std::move(path)) {}
        ~WavOutput() override { finish(); }

        bool supported() override { return true; }
        bool open(const std::string&) override
        {
            if (!m_started) {
                m_t0 = nowUs();
                m_started = true;
            }
            m_open = true;
            return true;
        }
        void close() override
        {
            for (auto& s : m_streams)
                s = Stream();
            m_open = false;
        }
        bool isOpen() const override { return m_open; }
        std::string openedName() const override { return std::string(); }
        bool lost() override { return false; }
        int openStream() override
        {
            for (int i = 0; i < 8; ++i) {
                if (!m_streams[i].used) {
                    m_streams[i] = Stream();
                    m_streams[i].used = true;
                    return i;
                }
            }
            return -1;
        }
        void closeStream(const int stream) override
        {
            if (stream >= 0 && stream < 8)
                m_streams[stream] = Stream();
        }
        int pending(const int stream) override
        {
            if (stream < 0 || stream >= 8 || !m_streams[stream].used)
                return 0;
            auto& s = m_streams[stream];
            const int64_t t = nowSample();
            while (!s.ends.empty() && s.ends.front() <= t)
                s.ends.pop_front();
            return static_cast<int>(s.ends.size());
        }
        bool canQueue(const int stream) override
        {
            return stream >= 0 && stream < 8 && m_streams[stream].used && m_streams[stream].ends.size() < 4;
        }
        bool queue(const int stream, const int16_t* pcm, const int samples) override
        {
            if (!canQueue(stream))
                return false;
            auto& s = m_streams[stream];
            const int64_t start = std::max(s.end, nowSample());
            if (start > s.end && s.end > 0)
                ++m_restarts;
            if (m_mix.size() < static_cast<size_t>(start + samples))
                m_mix.resize(static_cast<size_t>(start + samples), 0.0f);
            for (int i = 0; i < samples; ++i)
                m_mix[static_cast<size_t>(start + i)] += pcm[i] * s.gain;
            s.end = start + samples;
            s.ends.push_back(s.end);
            return true;
        }
        void setGain(const int stream, const float gain) override
        {
            if (stream >= 0 && stream < 8)
                m_streams[stream].gain = gain;
        }
        std::vector<std::string> devices() override { return { "wav" }; }

        void finish()
        {
            if (m_path.empty() || m_done)
                return;
            m_done = true;
            std::vector<int16_t> pcm(m_mix.size());
            for (size_t i = 0; i < m_mix.size(); ++i)
                pcm[i] = static_cast<int16_t>(std::lrint(std::clamp(m_mix[i], -32768.0f, 32767.0f)));
            wavio::writeWav(m_path, pcm);
        }

    private:
        struct Stream
        {
            bool used = false;
            int64_t end = 0;
            std::deque<int64_t> ends;
            float gain = 1.0f;
        };
        int64_t nowSample() const { return (nowUs() - m_t0) * 48 / 1000; }

        std::string m_path;
        bool m_started = false;
        bool m_open = false;
        bool m_done = false;
        int64_t m_t0 = 0;
        std::vector<float> m_mix;
        Stream m_streams[8];
        uint64_t m_restarts = 0;
    };

    // ---------------------------------------------------------------------
    // --unit

    int g_failures = 0;
    int g_checks = 0;

    void check(const bool ok, const std::string& name, const std::string& detail = std::string())
    {
        ++g_checks;
        if (!ok)
            ++g_failures;
        out({ { "check", name }, { "ok", ok }, { "detail", detail } });
    }

    std::string kinds(const std::vector<JitterBuffer::Kind>& v)
    {
        std::string s;
        for (const auto k : v) {
            switch (k) {
                case JitterBuffer::Kind::Frame:
                    s += 'F';
                    break;
                case JitterBuffer::Kind::Conceal:
                    s += 'C';
                    break;
                case JitterBuffer::Kind::Silence:
                    s += 'S';
                    break;
                default:
                    s += '.';
                    break;
            }
        }
        return s;
    }

    struct Arrival
    {
        int64_t at;
        uint8_t seq;
        bool end;
        uint8_t mark; // payload byte 0, to check the order played
    };

    // a player that pulls exactly when the previous frame has played (lead 0)
    std::string simulate(JitterBuffer& jb, const std::vector<Arrival>& arrivals, const int64_t until,
                         std::vector<int>* marks = nullptr)
    {
        std::vector<JitterBuffer::Kind> got;
        size_t next = 0;
        int64_t busyUntil = 0;
        uint8_t payload[80];
        for (int64_t t = 0; t <= until; ++t) {
            while (next < arrivals.size() && arrivals[next].at <= t) {
                std::memset(payload, arrivals[next].mark, sizeof(payload));
                jb.push(arrivals[next].seq, arrivals[next].end, payload, sizeof(payload), 1920, t);
                ++next;
            }
            if (t < busyUntil)
                continue;
            const auto r = jb.pull(t);
            if (r.kind == JitterBuffer::Kind::Idle)
                continue;
            got.push_back(r.kind);
            if (r.kind == JitterBuffer::Kind::Frame && marks)
                marks->push_back(r.data[0]);
            busyUntil = (r.kind == JitterBuffer::Kind::Frame || r.kind == JitterBuffer::Kind::Conceal) ? t + 40 : t + 1;
        }
        return kinds(got);
    }

    std::vector<Arrival> spurt(const int first, const int count, const int64_t at0, const bool end = true)
    {
        std::vector<Arrival> v;
        for (int i = 0; i < count; ++i) {
            const auto seq = static_cast<uint8_t>(first + i);
            v.push_back({ at0 + 40 * i, seq, end && i == count - 1, static_cast<uint8_t>(i) });
        }
        return v;
    }

    void unitProtocol()
    {
        using namespace voiceproto;
        uint8_t opus[240];
        for (int i = 0; i < 240; ++i)
            opus[i] = static_cast<uint8_t>(i * 7);
        uint8_t buf[256];
        size_t n = packUp(buf, 1, true, true, 200, opus, 80);
        check(n == 83 && buf[0] == kAudio && buf[1] == (1 | kEnd | kVad) && buf[2] == 200 && std::memcmp(buf + 3, opus, 80) == 0,
              "proto: packUp header and payload", std::to_string(n));
        check(packUp(buf, 0, false, false, 0, opus, 0) == 0, "proto: packUp refuses an empty payload");
        check(packUp(buf, 0, false, false, 0, opus, 241) == 0, "proto: packUp refuses 241 B");
        check(packUp(buf, 3, false, false, 0, opus, 10) == 0 && packUp(buf, -1, false, false, 0, opus, 10) == 0,
              "proto: packUp refuses slot 3 and -1");
        check(packUp(buf, 2, false, false, 0, opus, 240) == 243, "proto: packUp takes 240 B");

        // relay AUDIO
        uint8_t down[300];
        down[0] = kAudio;
        down[1] = makeFlags(2, true, false);
        down[2] = 0x34;
        down[3] = 0x12;
        down[4] = 9;
        std::memcpy(down + 5, opus, 50);
        int calls = 0;
        bool good = parseDown(down, 55, [&](int slot, bool end, bool vad, uint16_t sid, uint8_t seq, const uint8_t* p, size_t len) {
            ++calls;
            good = slot == 2 && end && !vad && sid == 0x1234 && seq == 9 && len == 50 && std::memcmp(p, opus, 50) == 0;
        });
        check(good && calls == 1, "proto: parseDown AUDIO (sid little-endian, flags, seq)");
        auto count = [&](const uint8_t* p, size_t len, bool& ok) {
            int c = 0;
            ok = parseDown(p, len, [&](int, bool, bool, uint16_t, uint8_t, const uint8_t*, size_t) { ++c; });
            return c;
        };
        bool ok = true;
        check(count(down, 5, ok) == 0 && !ok, "proto: AUDIO with no payload is refused");
        check(count(down, 5 + 241, ok) == 0 && !ok, "proto: AUDIO over 240 B (246 total) is refused");
        check(count(down, 5 + 240, ok) == 1 && ok, "proto: AUDIO of 245 B is taken");

        // BUNDLE of 3
        std::vector<uint8_t> b = { kBundle, 3 };
        for (int k = 0; k < 3; ++k) {
            const int len = 10 + k * 20;
            b.push_back(static_cast<uint8_t>(4 + len));
            b.push_back(makeFlags(k, k == 2, k == 1));
            b.push_back(static_cast<uint8_t>(k + 1));
            b.push_back(0);
            b.push_back(static_cast<uint8_t>(100 + k));
            b.insert(b.end(), opus, opus + len);
        }
        std::vector<int> sids, seqs, lens;
        ok = parseDown(b.data(), b.size(), [&](int, bool, bool, uint16_t sid, uint8_t seq, const uint8_t*, size_t len) {
            sids.push_back(sid);
            seqs.push_back(seq);
            lens.push_back(static_cast<int>(len));
        });
        check(ok && sids == std::vector<int>{ 1, 2, 3 } && seqs == std::vector<int>{ 100, 101, 102 } && lens == std::vector<int>{ 10, 30, 50 },
              "proto: BUNDLE of 3 frames");
        auto bad = b;
        bad[1] = 1;
        check(count(bad.data(), bad.size(), ok) == 0 && !ok, "proto: BUNDLE with n=1 is refused");
        bad = b;
        bad[1] = 9;
        check(count(bad.data(), bad.size(), ok) == 0 && !ok, "proto: BUNDLE with n=9 is refused");
        bad = b;
        bad.push_back(0);
        check(count(bad.data(), bad.size(), ok) == 3 && !ok, "proto: BUNDLE with trailing bytes is refused after its whole frames");
        bad = b;
        bad[2] = 250; // len over the message
        check(count(bad.data(), bad.size(), ok) == 0 && !ok, "proto: BUNDLE entry longer than the message is refused");
        bad = b;
        bad[2] = 4; // no opus
        check(count(bad.data(), bad.size(), ok) == 0 && !ok, "proto: BUNDLE entry without payload is refused");
        check(count(b.data(), 1, ok) == 0 && !ok, "proto: a 1-byte message is refused");
        uint8_t other[4] = { 0x03, 0, 0, 0 };
        check(count(other, 4, ok) == 0 && !ok, "proto: an unknown type is refused");
        check(seqDiff(2, 250) == 8 && seqDiff(250, 2) == -8 && seqDiff(0, 255) == 1 && seqDiff(127, 0) == 127 && seqDiff(128, 0) == -128,
              "proto: seqDiff wraps modulo 256");
    }

    void unitJitter()
    {
        using K = JitterBuffer::Kind;
        {
            JitterBuffer jb;
            std::vector<int> marks;
            const auto s = simulate(jb, spurt(0, 10, 0), 1000, &marks);
            check(s == "FFFFFFFFFFS" && jb.stats().conceal == 0, "jitter: in order, END ends the spurt", s);
            bool ordered = marks.size() == 10;
            for (size_t i = 0; ordered && i < marks.size(); ++i)
                ordered = marks[i] == static_cast<int>(i);
            check(ordered, "jitter: played in seq order");
        }
        {
            // seq 4 arrives before 3 (both before 3 is due)
            JitterBuffer jb;
            auto a = spurt(0, 8, 0);
            a[3].at = 150;
            a[4].at = 140;
            std::sort(a.begin(), a.end(), [](const Arrival& x, const Arrival& y) { return x.at < y.at; });
            std::vector<int> marks;
            const auto s = simulate(jb, a, 1000, &marks);
            check(s == "FFFFFFFFS" && marks == std::vector<int>{ 0, 1, 2, 3, 4, 5, 6, 7 } && jb.stats().late == 0,
                  "jitter: reorder inside the buffer plays in order", s);
        }
        {
            // seq 4 never comes
            JitterBuffer jb;
            auto a = spurt(0, 10, 0);
            a.erase(a.begin() + 4);
            const auto s = simulate(jb, a, 1000);
            check(s == "FFFFCFFFFFS" && jb.stats().conceal == 1, "jitter: a gap is concealed once", s);
        }
        {
            // the speaker vanished without END: 3 concealments, then silence
            JitterBuffer jb;
            const auto s = simulate(jb, spurt(0, 4, 0, false), 1000);
            check(s == "FFFFCCCS" && jb.idle(), "jitter: at most 3 concealments, then silence and idle", s);
        }
        {
            // a stall flushes 15 frames (600 ms) at once
            JitterBuffer jb;
            uint8_t p[80] = {};
            for (int i = 0; i < 15; ++i)
                jb.push(static_cast<uint8_t>(i), false, p, sizeof(p), 1920, 0);
            const int before = jb.bufferedMs();
            jb.maintain(20);
            check(before == 600 && jb.bufferedMs() <= 80 && jb.stats().trimmed == 13 && jb.stats().maxBufferedMs <= 400,
                  "jitter: 400 ms cap trims the oldest down to the target",
                  std::to_string(before) + " -> " + std::to_string(jb.bufferedMs()) + " ms, trimmed " + std::to_string(jb.stats().trimmed));
            const auto r = jb.pull(21);
            check(r.kind == K::Frame && jb.frames() == 1, "jitter: the newest frames are what plays after the cap");
        }
        {
            // 11 frames within 2 ms while playing: over the cap at once
            JitterBuffer jb;
            uint8_t p[80] = {};
            jb.push(0, false, p, sizeof(p), 1920, 0);
            jb.push(1, false, p, sizeof(p), 1920, 40);
            (void)jb.pull(40);
            for (int i = 2; i < 13; ++i)
                jb.push(static_cast<uint8_t>(i), false, p, sizeof(p), 1920, 400);
            jb.maintain(401); // within 10 ms of the last frame: only the cap applies
            check(jb.bufferedMs() <= 400, "jitter: the cap holds while frames still arrive", std::to_string(jb.bufferedMs()) + " ms");
            jb.maintain(415); // the burst is over: the stall rule brings it to the target
            check(jb.bufferedMs() <= jb.targetMs(), "jitter: a stall's backlog goes down to the target",
                  std::to_string(jb.bufferedMs()) + " ms, target " + std::to_string(jb.targetMs()));
        }
        {
            // two spurts, END on each: reset between them, both play whole
            JitterBuffer jb;
            auto a = spurt(0, 5, 0);
            auto b = spurt(5, 5, 600);
            a.insert(a.end(), b.begin(), b.end());
            const auto s = simulate(jb, a, 1500);
            check(s == "FFFFFSFFFFFS" && jb.stats().spurts == 2, "jitter: reset per spurt (buffering again)", s);
        }
        {
            // u8 wrap
            JitterBuffer jb;
            std::vector<int> marks;
            const auto s = simulate(jb, spurt(250, 12, 0), 1000, &marks);
            bool ordered = marks.size() == 12;
            for (size_t i = 0; ordered && i < marks.size(); ++i)
                ordered = marks[i] == static_cast<int>(i);
            check(s == "FFFFFFFFFFFFS" && ordered && jb.stats().late == 0, "jitter: seq 250..255,0..5 across the u8 wrap", s);
        }
        {
            JitterBuffer jb;
            uint8_t p[80] = {};
            jb.push(10, false, p, sizeof(p), 1920, 0);
            jb.push(11, false, p, sizeof(p), 1920, 40);
            jb.push(12, false, p, sizeof(p), 1920, 80);
            (void)jb.pull(80);
            (void)jb.pull(120);
            check(jb.push(10, false, p, sizeof(p), 1920, 130) == JitterBuffer::Push::Late && jb.stats().late == 1,
                  "jitter: a frame behind the play position is late");
            check(jb.push(12, false, p, sizeof(p), 1920, 131) == JitterBuffer::Push::Duplicate && jb.stats().dup == 1,
                  "jitter: a duplicate is dropped");
            check(jb.push(60, false, p, sizeof(p), 1920, 140) == JitterBuffer::Push::Restarted && jb.stats().resets == 1,
                  "jitter: 32+ ahead restarts the spurt");
            check(jb.push(61, false, p, 0, 1920, 141) == JitterBuffer::Push::Invalid &&
                      jb.push(61, false, p, 241, 1920, 141) == JitterBuffer::Push::Invalid,
                  "jitter: empty and oversize payloads are refused");
        }
        {
            // one frame alone: waits 120 ms, then plays and conceals out
            JitterBuffer jb;
            const auto s = simulate(jb, spurt(0, 1, 0, false), 500);
            JitterBuffer jb2;
            uint8_t p[80] = {};
            jb2.push(0, false, p, sizeof(p), 1920, 0);
            const bool waits = jb2.pull(119).kind == K::Idle && jb2.pull(120).kind == K::Frame;
            check(waits && s == "FCCCS", "jitter: a lone frame starts 120 ms after it came", s);
        }
        {
            JitterBuffer jb;
            uint8_t p[80] = {};
            jb.push(0, true, p, sizeof(p), 1920, 0);
            check(jb.pull(1).kind == K::Frame, "jitter: a spurt whose END is in starts at once");
        }
        {
            // lead: one frame of lead waits for 120 ms buffered
            JitterBuffer jb(40);
            uint8_t p[80] = {};
            jb.push(0, false, p, sizeof(p), 1920, 0);
            jb.push(1, false, p, sizeof(p), 1920, 40);
            const bool waits = jb.pull(41).kind == K::Idle;
            jb.push(2, false, p, sizeof(p), 1920, 80);
            check(waits && jb.pull(81).kind == K::Frame, "jitter: lead 40 starts at target + 40 ms");
        }
        {
            // arrival jitter of +-30 ms raises the target, within 80..240
            JitterBuffer jb;
            uint8_t p[80] = {};
            for (int i = 0; i < 60; ++i)
                jb.push(static_cast<uint8_t>(i), false, p, sizeof(p), 1920, 40 * i + ((i & 1) ? 30 : -30) + 100);
            const int t1 = jb.targetMs();
            JitterBuffer calm;
            for (int i = 0; i < 60; ++i)
                calm.push(static_cast<uint8_t>(i), false, p, sizeof(p), 1920, 40 * i);
            check(t1 > 150 && t1 <= 240 && calm.targetMs() == 80, "jitter: the target follows J (80 + 2J, capped at 240)",
                  "jittery " + std::to_string(t1) + " ms, calm " + std::to_string(calm.targetMs()) + " ms");
        }
        {
            // 60 ms frames (eco)
            JitterBuffer jb;
            uint8_t p[80] = {};
            jb.push(0, false, p, sizeof(p), 2880, 0);
            jb.push(1, false, p, sizeof(p), 2880, 60);
            check(jb.bufferedMs() == 120 && jb.pull(61).kind == K::Frame, "jitter: 60 ms frames count 60 ms each");
        }
    }

    void unitCodec()
    {
        // the e2e fixture's voice-like signal (180 Hz harmonics, 5 Hz AM)
        std::vector<int16_t> pcm(48000 * 2);
        for (size_t i = 0; i < pcm.size(); ++i) {
            const double t = i / 48000.0;
            const double pi2 = 6.283185307179586;
            const double v = 0.45 * (0.5 * std::sin(pi2 * 180 * t) + 0.3 * std::sin(pi2 * 360 * t) + 0.2 * std::sin(pi2 * 540 * t) +
                                     0.12 * std::sin(pi2 * 900 * t) + 0.08 * std::sin(pi2 * 1500 * t)) *
                             (0.65 + 0.35 * std::sin(pi2 * 5 * t));
            pcm[i] = static_cast<int16_t>(std::lrint(v * 32767));
        }
        for (int p = 0; p < 3; ++p) {
            OpusEnc enc;
            OpusDec dec;
            const bool opened = enc.open(p) && dec.open();
            const int frame = enc.frameSamples();
            std::vector<int16_t> decoded;
            size_t bytes = 0, frames = 0, biggest = 0;
            uint8_t packet[240];
            int16_t buf[voicecodec::kMaxFrameSamples];
            for (size_t at = 0; opened && at + frame <= pcm.size(); at += frame) {
                const int n = enc.encode(pcm.data() + at, packet, 240);
                if (n <= 0)
                    break;
                bytes += n;
                biggest = std::max(biggest, static_cast<size_t>(n));
                ++frames;
                const int got = dec.decode(packet, n, buf, voicecodec::kMaxFrameSamples);
                if (got != frame || voicecodec::packetSamples(packet, n) != frame)
                    break;
                decoded.insert(decoded.end(), buf, buf + got);
            }
            const double avg = frames ? static_cast<double>(bytes) / frames : 0;
            const double expect = voicecodec::preset(p).bitrate * (frame / 48000.0) / 8;
            // energy after the first 200 ms (codec start-up), against the same span of the input
            double si = 0, so = 0;
            const size_t from = 9600, upto = std::min(pcm.size(), decoded.size()) - 2000;
            for (size_t i = from; i < upto; ++i) {
                si += static_cast<double>(pcm[i]) * pcm[i];
                so += static_cast<double>(decoded[i]) * decoded[i];
            }
            const double diff = 10 * std::log10((so + 1) / (si + 1));
            const int plc = dec.conceal(buf, frame);
            check(opened && decoded.size() == frames * frame && frames > 0 && biggest <= 240 && avg > expect * 0.6 && avg < expect * 1.4 &&
                      std::fabs(diff) < 1.0 && plc == frame,
                  "codec: preset " + std::to_string(p) + " round trip",
                  "frame " + std::to_string(frame) + ", avg " + std::to_string(static_cast<int>(avg)) + " B (expect ~" +
                      std::to_string(static_cast<int>(expect)) + "), max " + std::to_string(biggest) + " B, energy " +
                      std::to_string(diff).substr(0, 5) + " dB, conceal " + std::to_string(plc));
        }
        check(voicecodec::packetSamples(nullptr, 0) <= 0, "codec: packetSamples refuses nothing");
    }

    int runUnit()
    {
        unitProtocol();
        unitJitter();
        unitCodec();
        out({ { "unit", "done" }, { "checks", g_checks }, { "failures", g_failures } });
        return g_failures == 0 ? 0 : 1;
    }

    // ---------------------------------------------------------------------
    // --compare

    int runCompare(const std::string& refPath, const std::string& outPath, const double minDb)
    {
        wavio::Audio ref, got;
        std::string err;
        if (!wavio::readWav(refPath, ref, err) || !wavio::readWav(outPath, got, err)) {
            out({ { "compare", "error" }, { "error", err } });
            return 2;
        }
        const size_t win = 4800;
        const auto envRef = wavio::envelope(ref.pcm, win);
        // prefix sums of the output's energy: any lag in O(1) per window
        std::vector<double> pre(got.pcm.size() + 1, 0.0);
        for (size_t i = 0; i < got.pcm.size(); ++i) {
            const double x = got.pcm[i] / 32768.0;
            pre[i + 1] = pre[i] + x * x;
        }
        auto envOut = [&](size_t start) { return 10.0 * std::log10((pre[start + win] - pre[start]) / win + 1e-12); };
        double best = 1e9;
        long bestLag = -1;
        size_t bestN = 0;
        const size_t maxLag = std::min<size_t>(48000 * 4, got.pcm.size());
        for (size_t lag = 0; lag < maxLag; lag += 48) {
            double sum = 0;
            size_t n = 0;
            for (size_t w = 0; w < envRef.size(); ++w) {
                const size_t start = lag + w * win;
                if (start + win > got.pcm.size())
                    break;
                if (envRef[w] < minDb)
                    continue;
                sum += std::fabs(envOut(start) - envRef[w]);
                ++n;
            }
            if (n >= 5 && sum / n < best) {
                best = sum / n;
                bestLag = static_cast<long>(lag);
                bestN = n;
            }
        }
        if (bestLag < 0) {
            out({ { "compare", "error" }, { "error", "no overlap with loud windows" } });
            return 2;
        }
        double maxAbs = 0, bias = 0;
        size_t within = 0, quietOk = 0, quietN = 0;
        std::vector<double> diffs;
        for (size_t w = 0; w < envRef.size(); ++w) {
            const size_t start = bestLag + w * win;
            if (start + win > got.pcm.size())
                break;
            const double d = envOut(start) - envRef[w];
            if (envRef[w] >= minDb) {
                diffs.push_back(std::round(d * 10) / 10);
                maxAbs = std::max(maxAbs, std::fabs(d));
                bias += d;
                if (std::fabs(d) <= 2.0)
                    ++within;
            } else {
                ++quietN;
                if (envOut(start) < minDb)
                    ++quietOk;
            }
        }
        out({ { "compare", "ok" }, { "lagMs", bestLag / 48.0 }, { "loudWindows", bestN }, { "meanAbsDb", best }, { "maxAbsDb", maxAbs },
              { "meanDiffDb", bias / std::max<size_t>(1, bestN) }, { "within2dB", static_cast<double>(within) / std::max<size_t>(1, bestN) },
              { "quietWindows", quietN }, { "quietStayQuiet", quietOk }, { "diffs", diffs } });
        return 0;
    }

    // ---------------------------------------------------------------------
    // --openal-check

    int runOpenALCheck()
    {
        auto capture = createOpenALCapture();
        auto playback = createOpenALPlayback();
        const auto ins = capture->devices();
        const auto outs = playback->devices();
        const bool sup = playback->supported();
        const bool capOpen = capture->open("", 48000);
        capture->close();
        const bool opened = playback->open("");
        int stream = opened ? playback->openStream() : -1;
        int queued = 0;
        if (stream >= 0) {
            std::vector<int16_t> tone(1920);
            for (int k = 0; k < 25; ++k) {
                for (int i = 0; i < 1920; ++i)
                    tone[i] = static_cast<int16_t>(std::lrint(8000 * std::sin(6.283185307179586 * 440 * (k * 1920 + i) / 48000.0)));
                while (!playback->canQueue(stream)) {
                    std::this_thread::sleep_for(std::chrono::milliseconds(5));
                    playback->pending(stream);
                }
                if (playback->queue(stream, tone.data(), 1920))
                    ++queued;
            }
            while (playback->pending(stream) > 0)
                std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
        // the game's context is untouched: on this thread our context is
        // current (thread-local), on any other thread nothing is
        const bool ownHere = alcGetCurrentContext() != nullptr;
        bool otherThreadNone = false;
        std::thread([&] { otherThreadNone = alcGetCurrentContext() == nullptr; }).join();
        const bool globalUntouched = ownHere && otherThreadNone;
        playback->close();
        out({ { "openal", "check" }, { "threadLocalContext", sup }, { "playbackOpened", opened }, { "stream", stream }, { "queued", queued },
              { "globalContextUntouched", globalUntouched }, { "captureOpened", capOpen }, { "inputs", ins }, { "outputs", outs } });
        return opened && stream >= 0 && queued == 25 && globalUntouched ? 0 : 1;
    }

    // ---------------------------------------------------------------------
    // talk / listen against a relay

    struct ProcSample
    {
        long rssKb = 0;
        long threads = 0;
        double cpuMs = 0;
    };

    ProcSample procSelf()
    {
        ProcSample s;
        std::ifstream st("/proc/self/status");
        std::string line;
        while (std::getline(st, line)) {
            if (line.rfind("VmRSS:", 0) == 0)
                s.rssKb = std::atol(line.c_str() + 6);
            else if (line.rfind("Threads:", 0) == 0)
                s.threads = std::atol(line.c_str() + 8);
        }
        std::ifstream sf("/proc/self/stat");
        std::string all((std::istreambuf_iterator<char>(sf)), std::istreambuf_iterator<char>());
        const auto rp = all.rfind(')');
        if (rp != std::string::npos) {
            std::vector<std::string> f;
            std::string cur;
            for (size_t i = rp + 2; i < all.size(); ++i) {
                if (all[i] == ' ') {
                    f.push_back(cur);
                    cur.clear();
                } else {
                    cur += all[i];
                }
            }
            // fields after ')': state is [0]; utime [11], stime [12]
            if (f.size() > 12) {
                const double hz = static_cast<double>(sysconf(_SC_CLK_TCK));
                s.cpuMs = (std::atof(f[11].c_str()) + std::atof(f[12].c_str())) * 1000.0 / hz;
            }
        }
        return s;
    }

    struct Args
    {
        std::map<std::string, std::string> v;
        bool has(const std::string& k) const { return v.count(k) > 0; }
        std::string str(const std::string& k, const std::string& d = std::string()) const
        {
            const auto it = v.find(k);
            return it == v.end() ? d : it->second;
        }
        double num(const std::string& k, const double d) const
        {
            const auto it = v.find(k);
            return it == v.end() || it->second.empty() ? d : std::atof(it->second.c_str());
        }
    };

    std::atomic<bool> g_interrupted{ false };

    int runSession(const Args& a)
    {
        const std::string url = a.str("--url");
        const std::string tok = a.str("--tok");
        const std::string room = a.str("--room");
        const bool send = a.has("--send");
        const bool recv = a.has("--recv");
        const bool quiet = a.has("--quiet");
        const double dur = a.num("--dur", 12);
        const int slot = static_cast<int>(a.num("--slot", 0));
        const bool vad = a.has("--vad");
        const bool localTest = a.has("--local-test"); // "Testar microfone": no relay
        const bool meterOnly = a.has("--meter-only"); // the settings window's meter: no relay
        const bool noRelay = localTest || meterOnly;
        if (!noRelay && (url.empty() || tok.empty())) {
            out({ { "error", "--url and --tok are needed" } });
            return 2;
        }
        std::vector<int16_t> input;
        if (send) {
            wavio::Audio wav;
            std::string err;
            if (!wavio::readWav(a.str("--send"), wav, err)) {
                out({ { "error", err } });
                return 2;
            }
            input = std::move(wav.pcm);
        }

        NativeVoiceOptions o;
        WavInput* wavIn = nullptr;
        WavOutput* wavOut = nullptr;
        const bool loop = a.has("--loop");
        const double lateMic = a.num("--late-mic", 0);
        const int64_t startUs = nowUs();
        o.makeInput = [&]() -> std::unique_ptr<AudioInput> {
            if (!send && lateMic <= 0)
                return std::make_unique<NoInput>();
            auto in = std::make_unique<WavInput>(input, loop, lateMic > 0 ? startUs + static_cast<int64_t>(lateMic * 1e6) : 0,
                                                 static_cast<int>(a.num("--slow-open", 0)));
            wavIn = in.get();
            return in;
        };
        const bool openalOut = recv && !a.has("--wav-out");
        o.makeOutput = [&]() -> std::unique_ptr<AudioOutput> {
            if (openalOut)
                return createOpenALPlayback();
            auto w = std::make_unique<WavOutput>(recv ? a.str("--recv") : std::string());
            wavOut = w.get();
            return w;
        };
        o.caFile = a.str("--ca");
        o.log = [](int level, const std::string& text) { out({ { "log", text }, { "level", level } }); };
        o.lossRate = a.num("--loss", 0);
        o.jitterMs = static_cast<int>(a.num("--jitter", 0));
        o.stallMs = static_cast<int>(a.num("--stall", 0));
        o.stallEveryMs = static_cast<int>(a.num("--stall-every", 0));
        o.seed = static_cast<uint32_t>(a.num("--seed", 1));
        // --ptt-window A,B: the push-to-talk key from A to B s after the join
        // (else held for the whole run); --global-key A,B: the background key
        auto window = [&](const std::string& k, double& from, double& to) {
            const std::string v = a.str(k);
            const auto comma = v.find(',');
            if (v.empty() || comma == std::string::npos)
                return false;
            from = std::atof(v.substr(0, comma).c_str());
            to = std::atof(v.substr(comma + 1).c_str());
            return true;
        };
        double pttFrom = 0, pttTo = 0, keyFrom = 0, keyTo = 0;
        const bool pttWindow = window("--ptt-window", pttFrom, pttTo);
        const bool globalKey = window("--global-key", keyFrom, keyTo);
        std::atomic<int64_t> joinedAtAbs{ 0 };
        if (globalKey) {
            o.keyHeld = [&](int) {
                const int64_t j = joinedAtAbs.load();
                if (!j)
                    return false;
                const double s = (nowMs() - j) / 1000.0;
                return s >= keyFrom && s < keyTo;
            };
        }

        std::mutex m;
        std::condition_variable cv;
        std::deque<VoiceEvent> events;
        const ProcSample before = procSelf(); // the process without the engine
        const int64_t t0 = nowMs();
        auto engine = createNativeVoiceEngine(
            [&](VoiceEvent&& e) {
                std::lock_guard<std::mutex> lock(m);
                events.push_back(std::move(e));
                cv.notify_one();
            },
            o);

        engine->setPreset(static_cast<int>(a.num("--preset", 0)));
        engine->setInputGain(static_cast<float>(a.num("--gain", 1)));
        engine->setOutputVolume(static_cast<float>(a.num("--vol", 1)));
        engine->setMode(vad);
        engine->setVadThreshold(static_cast<float>(a.num("--vad-db", -40)));
        engine->setSelfMuted(false);
        engine->setDeafened(false);
        engine->setInputDevice("");
        engine->setOutputDevice("");
        if (globalKey)
            engine->setGlobalPtt(0x56); // V
        if (globalKey && room.empty())
            joinedAtAbs = nowMs(); // no room to wait for
        double presetAt = -1, presetTo = 0;
        const bool presetChange = window("--preset-at", presetAt, presetTo);
        const double meterOffAt = a.num("--meter-off-at", -1);
        bool meterOn = false;
        if (meterOnly) {
            engine->setMeter(true);
            meterOn = true;
        } else if (localTest) {
            engine->startLocalTest(true);
            if (a.has("--meter")) {
                engine->setMeter(true);
                meterOn = true;
            }
        } else {
            engine->connect(url, tok, "win", "voz-native-test");
        }

        std::map<std::string, int> counts;
        int sid = 0;
        bool joined = false;
        int64_t joinedAt = 0, talkOnAt = 0, firstSpkAt = 0;
        json lastStats;
        int closeCode = 0;
        bool closed = false;
        bool released = false;
        bool stopping = false;
        int64_t stopAt = 0;
        int64_t nextStats = t0 + 1000;
        ProcSample p0;
        int64_t p0At = 0;
        std::vector<json> procLog;
        const double terminateAt = a.num("--terminate-at", -1);
        double terminateMs = -1;
        bool terminated = false;
        int64_t micOkAt = -1, devicesAt = -1;
        json timeline = json::array();

        auto handle = [&](VoiceEvent& e) {
            ++counts[e.type];
            const int64_t t = nowMs() - t0;
            if (e.type == "stats") {
                lastStats = json::parse(e.s, nullptr, false);
                if (lastStats.is_object() && lastStats.contains("up"))
                    timeline.push_back({ t, lastStats["up"].value("f", 0), lastStats["up"].value("b", 0), lastStats["up"].value("encNew", 0) });
                return;
            }
            if (e.type == "mic" && e.s == "ok" && micOkAt < 0)
                micOkAt = t;
            if (e.type == "devices" && devicesAt < 0) {
                const auto lists = json::parse(e.s, nullptr, false);
                if (lists.is_object() && lists.contains("i") && lists["i"].is_array() && !lists["i"].empty())
                    devicesAt = t;
            }
            if (e.type == "level")
                return;
            if (!quiet || e.type == "state" || e.type == "talk" || e.type == "mic" || (e.type == "spk" && counts["spk"] <= 6))
                out({ { "t", t }, { "ev", e.type }, { "s", e.type == "ctl" ? e.s.substr(0, 160) : e.s }, { "a", e.a }, { "b", e.b } });
            if (e.type == "state" && e.s == "closed") {
                closed = true;
                closeCode = e.a;
            } else if (e.type == "ctl") {
                const auto msg = json::parse(e.s, nullptr, false);
                if (!msg.is_object())
                    return;
                const auto type = msg.value("t", std::string());
                if (type == "welcome") {
                    sid = msg.value("sid", 0);
                    if (!room.empty())
                        engine->sendControl(json({ { "t", "join" }, { "room", room } }).dump());
                } else if (type == "roster" && msg.value("room", std::string()) == room && !joined) {
                    joined = true;
                    joinedAt = t;
                    joinedAtAbs = nowMs();
                    if (send && !vad && !pttWindow && !globalKey)
                        engine->setTransmit(slot); // push-to-talk held for the run
                }
            } else if (e.type == "talk" && e.a >= 0 && !talkOnAt) {
                talkOnAt = t;
            } else if (e.type == "spk" && e.b == 1 && !firstSpkAt) {
                firstSpkAt = t;
            }
        };

        while (!g_interrupted) {
            std::deque<VoiceEvent> batch;
            {
                std::unique_lock<std::mutex> lock(m);
                cv.wait_for(lock, std::chrono::milliseconds(20), [&] { return !events.empty(); });
                batch.swap(events);
            }
            for (auto& e : batch)
                handle(e);
            const int64_t t = nowMs();
            if (closed && !stopping)
                break;
            if (terminateAt >= 0 && !terminated && t - t0 >= terminateAt * 1000) {
                const auto before = nowUs();
                engine->terminate();
                terminateMs = (nowUs() - before) / 1000.0;
                terminated = true;
                break;
            }
            if (pttWindow && joinedAtAbs.load()) {
                static int pttState = 0; // 0 before, 1 held, 2 released
                const double s = (t - joinedAtAbs.load()) / 1000.0;
                if (pttState == 0 && s >= pttFrom) {
                    engine->setTransmit(slot);
                    pttState = 1;
                } else if (pttState == 1 && s >= pttTo) {
                    engine->setTransmit(-1);
                    pttState = 2;
                }
            }
            if (presetChange && presetAt >= 0 && t - t0 >= presetAt * 1000) {
                engine->setPreset(static_cast<int>(presetTo));
                presetAt = -1;
            }
            if (meterOn && meterOffAt >= 0 && t - t0 >= meterOffAt * 1000) {
                engine->setMeter(false);
                meterOn = false;
            }
            if (t >= nextStats) {
                nextStats += 1000;
                engine->requestStats();
                const auto ps = procSelf();
                if ((joined || noRelay) && !p0At) {
                    p0 = ps;
                    p0At = t;
                }
                procLog.push_back({ { "t", t - t0 }, { "rssKb", ps.rssKb }, { "cpuMs", ps.cpuMs }, { "threads", ps.threads } });
            }
            if (!stopping && t - t0 >= dur * 1000) {
                stopping = true;
                stopAt = t;
                if (send && !vad && !pttWindow && !globalKey) {
                    engine->setTransmit(-1);
                    released = true;
                }
                if (vad)
                    engine->setMode(false);
                if (localTest)
                    engine->startLocalTest(false);
                if (noRelay)
                    engine->setMeter(false);
            }
            if (stopping && t - stopAt >= 1500) {
                engine->requestStats();
                std::this_thread::sleep_for(std::chrono::milliseconds(200));
                std::deque<VoiceEvent> rest;
                {
                    std::lock_guard<std::mutex> lock(m);
                    rest.swap(events);
                }
                for (auto& e : rest)
                    handle(e);
                break;
            }
        }
        const auto p1 = procSelf();
        const int64_t t1 = nowMs();
        // from the caller's thread, as Lua asks when the settings window opens
        const auto inputsAtEnd = terminated ? std::vector<std::string>() : engine->getInputDevices();
        if (!terminated) {
            engine->disconnect();
            const auto before = nowUs();
            engine->terminate();
            terminateMs = (nowUs() - before) / 1000.0;
        }
        const int micOpens = wavIn ? wavIn->opens() : 0;
        const int micTries = wavIn ? wavIn->tries() : 0;
        if (wavOut)
            wavOut->finish(); // before the engine (which owns it) goes
        wavIn = nullptr;
        wavOut = nullptr;
        engine.reset();
        const double span = p0At ? static_cast<double>(t1 - p0At) : 0;
        json summary = { { "summary", "session" },
                         { "sid", sid },
                         { "joinedAtMs", joinedAt },
                         { "talkOnAtMs", talkOnAt },
                         { "firstSpkAtMs", firstSpkAt },
                         { "events", counts },
                         { "closed", closed },
                         { "closeCode", closeCode },
                         { "released", released },
                         { "terminateMs", terminateMs },
                         { "terminatedEarly", terminated },
                         { "rssKb", p1.rssKb },
                         { "rssKbBefore", before.rssKb },
                         { "rssKbAtJoin", p0.rssKb },
                         { "threads", p1.threads },
                         { "cpuPctOfCore", span > 0 ? (p1.cpuMs - p0.cpuMs) * 100.0 / span : 0.0 },
                         { "micOpens", micOpens },
                         { "micTries", micTries },
                         { "micOkAtMs", micOkAt },
                         { "devicesAtMs", devicesAt },
                         { "inputsAtEnd", inputsAtEnd },
                         { "timeline", timeline },
                         { "talkEdges", counts["talk"] },
                         { "stats", lastStats } };
        out(summary);
        if (a.has("--stats-out")) {
            std::ofstream f(a.str("--stats-out"));
            summary["proc"] = procLog;
            f << summary.dump(1) << "\n";
        }
        return closed && !terminated && closeCode != 1000 ? 3 : 0;
    }
}

int main(int argc, char** argv)
{
    std::signal(SIGINT, [](int) { g_interrupted = true; });
    std::signal(SIGTERM, [](int) { g_interrupted = true; });
    std::signal(SIGPIPE, SIG_IGN);
    Args a;
    std::vector<std::string> positional;
    for (int i = 1; i < argc; ++i) {
        std::string k = argv[i];
        if (k.rfind("--", 0) == 0) {
            const bool flag = k == "--unit" || k == "--loop" || k == "--vad" || k == "--wav-out" || k == "--quiet" ||
                              k == "--openal-check" || k == "--local-test" || k == "--meter" || k == "--meter-only" ||
                              (k == "--recv" && (i + 1 >= argc || std::string(argv[i + 1]).rfind("--", 0) == 0));
            if (flag || i + 1 >= argc)
                a.v[k] = "";
            else
                a.v[k] = argv[++i];
        } else {
            positional.push_back(k);
        }
    }
    if (a.has("--unit"))
        return runUnit();
    if (a.has("--compare"))
        return runCompare(a.str("--compare"), positional.empty() ? std::string() : positional[0], a.num("--min-db", -35));
    if (a.has("--openal-check"))
        return runOpenALCheck();
    if (a.has("--url") || a.has("--local-test") || a.has("--meter-only"))
        return runSession(a);
    std::cerr << "usage: see the comment at the top of main.cpp\n";
    return 2;
}
