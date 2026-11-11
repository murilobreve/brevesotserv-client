/*
 * Mythos Voz: the jitter buffer of one speaker (protocol I of the voice plan;
 * the browser engine's mv-mixer holds the same policy over decoded PCM, this
 * one holds Opus packets and the native engine decodes on pull).
 *
 * - Frames are keyed by their u8 seq, compared modulo 256.
 * - A talk spurt starts playing once target + lead ms are buffered, or
 *   120 ms + (target - 80) + lead after its first frame, or at once when its
 *   END frame is in. lead is how far ahead of the ear the caller pulls: the
 *   native engine keeps up to two frames queued in OpenAL, so it pulls one
 *   frame early and asks for one frame of lead; the browser pulls exactly
 *   when due (lead 0).
 * - J: moving average (gain 1/16) of |arrival interval - frame duration|;
 *   target = clamp(80 + 2J, 80, 240) ms.
 * - Hard cap 400 ms, and a TCP stall's backlog (more than 2 frames over
 *   target + lead once 10 ms pass without a frame): the oldest frames go,
 *   down to target + lead.
 * - A frame missing when due: Conceal (the caller runs the decoder's loss
 *   concealment), at most 3 in a row; then, or after the END frame, the
 *   spurt is over: Silence once, then Idle until the next frame.
 * - Late frames (behind the play position) and duplicates are dropped; a
 *   frame 32 or more ahead is a new spurt after a gap we did not see end.
 *
 * Standard library only.
 */

#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

class JitterBuffer
{
public:
    static constexpr int kSlots = 32; // window ahead of the play position
    static constexpr size_t kMaxBytes = 240;
    static constexpr int kCapMs = 400;

    enum class Kind : uint8_t
    {
        Idle, // nothing to play now (empty, or still buffering)
        Frame, // data/size: the next Opus packet
        Conceal, // the next frame is missing: conceal `samples`
        Silence, // the spurt just ended (reported once)
    };

    struct Out
    {
        Kind kind = Kind::Idle;
        const uint8_t* data = nullptr; // valid until the next push or pull
        size_t size = 0;
        int samples = 0;
    };

    enum class Push : uint8_t
    {
        Stored,
        Restarted, // stored as the first frame of a new spurt (far ahead)
        Late,
        Duplicate,
        Invalid,
    };

    struct Stats
    {
        uint32_t late = 0;
        uint32_t conceal = 0;
        uint32_t trimmed = 0;
        uint32_t played = 0;
        uint32_t spurts = 0;
        uint32_t dup = 0;
        uint32_t resets = 0;
        int maxBufferedMs = 0; // after the cap and the stall rule
    };

    explicit JitterBuffer(int leadMs = 0) : m_leadMs(leadMs) {}

    // samples: the packet's duration at 48 kHz (opus_packet_get_nb_samples)
    Push push(uint8_t seq, bool end, const uint8_t* data, size_t size, int samples, int64_t nowMs);
    Out pull(int64_t nowMs);

    void reset();
    // the cap and the stall rule, without pulling
    void maintain(int64_t nowMs)
    {
        if (m_state != State::Idle)
            trim(nowMs);
    }
    void setLeadMs(int ms) { m_leadMs = ms < 0 ? 0 : ms; }

    bool idle() const { return m_state == State::Idle; }
    bool playing() const { return m_state == State::Playing; }
    int targetMs() const { return m_targetMs; }
    int bufferedMs() const { return m_bufferedMs; }
    int frames() const { return m_count; }
    double jitterMs() const { return m_jitter; }
    const Stats& stats() const { return m_stats; }

private:
    enum class State : uint8_t
    {
        Idle,
        Buffering,
        Playing,
    };

    struct Slot
    {
        bool used = false;
        bool end = false;
        uint8_t seq = 0;
        uint8_t size = 0;
        uint16_t samples = 0;
        uint8_t data[kMaxBytes] = {};
    };

    Slot& slot(uint8_t seq) { return m_slots[seq % kSlots]; }
    void clear();
    void restart(uint8_t seq, int64_t nowMs);
    void drop(Slot& s);
    void trim(int64_t nowMs);
    void trimTo(int keepMs);
    Out advance(int depth);

    std::array<Slot, kSlots> m_slots{};
    State m_state = State::Idle;
    uint8_t m_next = 0;
    int m_count = 0;
    int m_bufferedMs = 0;
    int m_leadMs = 0;
    int m_targetMs = 80;
    int m_frameMs = 40; // the last frame's duration
    double m_jitter = 0;
    int m_prevSeq = -1;
    int64_t m_prevAt = 0;
    int64_t m_firstAt = 0;
    int64_t m_lastAt = 0;
    bool m_hasLast = false; // a frame of this spurt was played
    int m_lastSamples = 1920;
    int m_miss = 0;
    bool m_endAfter = false; // the frame played last carried END
    bool m_hasEnd = false; // an END frame is buffered
    uint8_t m_out[kMaxBytes] = {};
    Stats m_stats;
};
