/*
 * Mythos Voz: binary audio framing (protocol C, D and E of the voice plan;
 * tools/voz/wire/proto.go in the server repository is the reference).
 *
 *   client -> relay  AUDIO  [0x01][flags][seq][opus 1-240 B]
 *   relay -> client  AUDIO  [0x01][flags][sid lo][sid hi][seq][opus]
 *   relay -> client  BUNDLE [0x02][n 2-8] n x ([len = 4+opus][flags][sid lo][sid hi][seq][opus])
 *
 * flags: bits 0-1 room slot (0 party, 1 guild/officers, 2 public/stage/echo,
 * 3 near), bit 2 END (last frame of a talk spurt), bit 3 VAD (voice
 * activation), bits 4-7 zero.
 *
 * The browser engine does this in mythos-voice.js; this header is for the
 * native engine (voiceengine_native.cpp) and its Linux test harness
 * (tools/voz-native-test). Standard library only.
 */

#pragma once

#include <cstddef>
#include <cstdint>

namespace voiceproto
{
    constexpr uint8_t kAudio = 0x01;
    constexpr uint8_t kBundle = 0x02;
    constexpr size_t kUpHeader = 3;
    constexpr size_t kDownHeader = 5;
    constexpr size_t kMaxOpus = 240;
    constexpr size_t kMaxBundle = 8;
    constexpr size_t kSpeechMin = 10; // payloads over this are speech
    constexpr int kSlots = 4; // room slots 0-3 (3: near, proximity voice)

    constexpr uint8_t kSlotMask = 0x03;
    constexpr uint8_t kEnd = 0x04;
    constexpr uint8_t kVad = 0x08;

    constexpr uint8_t makeFlags(int slot, bool end, bool vad)
    {
        return static_cast<uint8_t>((slot & kSlotMask) | (end ? kEnd : 0) | (vad ? kVad : 0));
    }

    // Writes a client AUDIO message into out (at least kUpHeader + n bytes).
    // Returns its length, or 0 when the payload is empty or too big.
    inline size_t packUp(uint8_t* out, int slot, bool end, bool vad, uint8_t seq, const uint8_t* opus, size_t n)
    {
        if (n < 1 || n > kMaxOpus || slot < 0 || slot >= kSlots)
            return 0;
        out[0] = kAudio;
        out[1] = makeFlags(slot, end, vad);
        out[2] = seq;
        for (size_t i = 0; i < n; ++i)
            out[kUpHeader + i] = opus[i];
        return kUpHeader + n;
    }

    // Calls onFrame(slot, end, vad, sid, seq, opus, opusLen) for each frame
    // of a relay AUDIO or BUNDLE message. Returns false (after the frames
    // that were whole) on a malformed message.
    template<typename F>
    bool parseDown(const uint8_t* p, size_t n, F&& onFrame)
    {
        auto one = [&](const uint8_t* e, size_t len) {
            // e: [flags][sid lo][sid hi][seq][opus], len = 4 + opus length
            const uint8_t flags = e[0];
            onFrame(static_cast<int>(flags & kSlotMask), (flags & kEnd) != 0, (flags & kVad) != 0,
                    static_cast<uint16_t>(e[1] | (e[2] << 8)), e[3], e + 4, len - 4);
        };
        if (n < 2)
            return false;
        if (p[0] == kAudio) {
            if (n <= kDownHeader || n > kDownHeader + kMaxOpus)
                return false;
            one(p + 1, n - 1);
            return true;
        }
        if (p[0] != kBundle)
            return false;
        const size_t count = p[1];
        if (count < 2 || count > kMaxBundle)
            return false;
        size_t at = 2;
        for (size_t i = 0; i < count; ++i) {
            if (at >= n)
                return false;
            const size_t len = p[at];
            if (len <= kDownHeader - 1 || len > kDownHeader - 1 + kMaxOpus || at + 1 + len > n)
                return false;
            one(p + at + 1, len);
            at += 1 + len;
        }
        return at == n;
    }

    // seq distance a - b modulo 256, in -128..127
    constexpr int seqDiff(uint8_t a, uint8_t b)
    {
        return static_cast<int>(static_cast<int8_t>(static_cast<uint8_t>(a - b)));
    }
}
