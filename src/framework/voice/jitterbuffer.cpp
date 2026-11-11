/*
 * Mythos Voz: the jitter buffer of one speaker (see jitterbuffer.h).
 */

#include "jitterbuffer.h"

#include <algorithm>
#include <cmath>
#include <cstring>

namespace
{
    // seq distance a - b modulo 256, in -128..127
    int seqDistance(const uint8_t a, const uint8_t b)
    {
        return static_cast<int>(static_cast<int8_t>(static_cast<uint8_t>(a - b)));
    }

    int msOf(const int samples) { return (std::max)(1, (samples + 24) / 48); }
}

void JitterBuffer::clear()
{
    for (auto& s : m_slots)
        s.used = false;
    m_count = 0;
    m_bufferedMs = 0;
}

void JitterBuffer::reset()
{
    clear();
    m_state = State::Idle;
    m_hasLast = false; // a new spurt never conceals with the old one's tail
    m_miss = 0;
    m_endAfter = false;
    m_hasEnd = false;
    m_prevSeq = -1;
}

void JitterBuffer::restart(const uint8_t seq, const int64_t nowMs)
{
    m_state = State::Buffering;
    m_next = seq;
    m_firstAt = nowMs;
}

void JitterBuffer::drop(Slot& s)
{
    s.used = false;
    m_count = (std::max)(0, m_count - 1);
    m_bufferedMs = m_count > 0 ? (std::max)(0, m_bufferedMs - msOf(s.samples)) : 0;
}

JitterBuffer::Push JitterBuffer::push(const uint8_t seq, const bool end, const uint8_t* data, const size_t size,
                                      const int samples, const int64_t nowMs, const int room)
{
    if (!data || size < 1 || size > kMaxBytes || samples < 1 || samples > 5760)
        return Push::Invalid;
    const int frameMs = msOf(samples);
    Push result = Push::Stored;
    if (m_state == State::Idle) {
        restart(seq, nowMs);
        ++m_stats.spurts;
    } else {
        const int d = seqDistance(seq, m_next);
        if (d < 0) {
            ++m_stats.late;
            return Push::Late;
        }
        if (d >= kSlots) {
            // far ahead: a new talk spurt after a gap we did not see end
            ++m_stats.resets;
            reset();
            restart(seq, nowMs);
            result = Push::Restarted;
        }
    }
    // J (RFC 3550 style), over arrivals 1-4 frames apart
    if (m_prevSeq >= 0 && nowMs > m_prevAt) {
        const int k = (seq - m_prevSeq) & 255;
        if (k >= 1 && k <= 4) {
            const double dev = std::fabs(static_cast<double>(nowMs - m_prevAt) - k * frameMs);
            m_jitter += (dev - m_jitter) / 16.0;
        }
    }
    m_prevSeq = seq;
    m_prevAt = nowMs;
    m_lastAt = nowMs;
    m_targetMs = std::clamp(static_cast<int>(std::lround(80 + 2 * m_jitter)), 80, 240);

    Slot& s = slot(seq);
    if (s.used && s.seq == seq) {
        ++m_stats.dup;
        return Push::Duplicate;
    }
    if (s.used)
        drop(s); // cannot happen inside the window; kept safe
    s.used = true;
    s.end = end;
    s.seq = seq;
    s.size = static_cast<uint8_t>(size);
    s.room = static_cast<uint8_t>(room & 3);
    s.samples = static_cast<uint16_t>(samples);
    std::memcpy(s.data, data, size);
    ++m_count;
    m_bufferedMs += frameMs;
    m_frameMs = frameMs;
    if (end)
        m_hasEnd = true;
    return result;
}

void JitterBuffer::trim(const int64_t nowMs)
{
    const int keep = m_targetMs + m_leadMs;
    const bool cap = m_bufferedMs > kCapMs;
    const bool stall = m_bufferedMs > keep + 2 * m_frameMs && nowMs - m_lastAt > 10;
    if (cap || stall)
        trimTo(keep);
    // what the buffer holds once the rules ran (frames arrive between ticks)
    m_stats.maxBufferedMs = (std::max)(m_stats.maxBufferedMs, m_bufferedMs);
}

void JitterBuffer::trimTo(const int keep)
{
    for (int i = 0; i < 256 && m_count > 0 && m_bufferedMs > keep; ++i) {
        Slot& s = slot(m_next);
        if (s.used && s.seq == m_next) {
            if (s.end)
                m_hasEnd = false;
            drop(s);
            ++m_stats.trimmed;
        }
        m_next = static_cast<uint8_t>(m_next + 1);
    }
}

JitterBuffer::Out JitterBuffer::pull(const int64_t nowMs)
{
    if (m_state == State::Idle)
        return {};
    trim(nowMs);
    if (m_state == State::Buffering) {
        const int64_t wait = 120 + (m_targetMs - 80) + m_leadMs;
        if (m_bufferedMs >= m_targetMs + m_leadMs || nowMs - m_firstAt >= wait || m_hasEnd)
            m_state = State::Playing;
        else
            return {};
    }
    return advance(0);
}

JitterBuffer::Out JitterBuffer::advance(const int depth)
{
    Slot& s = slot(m_next);
    if (s.used && s.seq == m_next) {
        Out out;
        out.kind = Kind::Frame;
        std::memcpy(m_out, s.data, s.size);
        out.data = m_out;
        out.size = s.size;
        out.samples = s.samples;
        out.slot = s.room;
        m_lastSlot = s.room;
        m_endAfter = s.end;
        if (s.end)
            m_hasEnd = false;
        m_lastSamples = s.samples;
        m_hasLast = true;
        m_miss = 0;
        drop(s);
        m_next = static_cast<uint8_t>(m_next + 1);
        ++m_stats.played;
        return out;
    }
    if (!m_hasLast && m_count > 0 && depth == 0) {
        // the first frames never came (dropped as stale): start at the
        // oldest one buffered
        for (int skip = 1; skip < kSlots; ++skip) {
            const auto seq = static_cast<uint8_t>(m_next + skip);
            const Slot& t = slot(seq);
            if (t.used && t.seq == seq) {
                m_next = seq;
                return advance(1);
            }
        }
    }
    if (m_endAfter || m_miss >= 3 || !m_hasLast) {
        reset();
        Out out;
        out.kind = Kind::Silence;
        return out;
    }
    ++m_miss;
    m_next = static_cast<uint8_t>(m_next + 1);
    ++m_stats.conceal;
    Out out;
    out.kind = Kind::Conceal;
    out.samples = m_lastSamples;
    out.slot = m_lastSlot;
    return out;
}
