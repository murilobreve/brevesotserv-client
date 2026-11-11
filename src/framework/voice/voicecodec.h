/*
 * Mythos Voz: libopus wrappers for the native engine (protocol B of the
 * voice plan). 48 kHz mono, 16-bit PCM.
 *
 * Presets (the same as the browser engine's PRESETS):
 *   0 normal  16 kbps CVBR, 40 ms (1920 samples), wideband
 *   1 eco     12 kbps CVBR, 60 ms (2880 samples), wideband
 *   2 high    24 kbps CVBR, 40 ms (1920 samples), super-wideband
 * Encoder: APPLICATION_VOIP, SIGNAL_VOICE, complexity 5, no in-band FEC, no
 * DTX, packet loss 0. Decoders read the frame size from each packet, so
 * presets mix freely in a room.
 *
 * Only libopus and the standard library: the Linux harness builds this file
 * on its own (tools/voz-native-test).
 */

#pragma once

#include <cstddef>
#include <cstdint>

struct OpusEncoder;
struct OpusDecoder;

namespace voicecodec
{
    constexpr int kRate = 48000;
    constexpr int kMaxFrameSamples = 5760; // 120 ms, the longest Opus packet

    struct Preset
    {
        int bitrate;
        int frameSamples;
        int maxBandwidth; // OPUS_BANDWIDTH_*
    };

    // the preset table; an unknown index gives normal
    const Preset& preset(int index);

    // samples per channel in one Opus packet at 48 kHz; <= 0 if malformed
    int packetSamples(const uint8_t* data, size_t size);
}

class OpusEnc
{
public:
    OpusEnc() = default;
    ~OpusEnc();
    OpusEnc(const OpusEnc&) = delete;
    OpusEnc& operator=(const OpusEnc&) = delete;

    bool open(int preset);
    void close();
    bool isOpen() const { return m_enc != nullptr; }
    int presetIndex() const { return m_preset; }
    int frameSamples() const { return m_frameSamples; }

    // one frame of frameSamples() samples; the packet's length, or < 0 on error
    int encode(const int16_t* pcm, uint8_t* out, int maxBytes);

private:
    OpusEncoder* m_enc = nullptr;
    int m_preset = -1;
    int m_frameSamples = 0;
};

class OpusDec
{
public:
    OpusDec() = default;
    ~OpusDec();
    OpusDec(const OpusDec&) = delete;
    OpusDec& operator=(const OpusDec&) = delete;

    bool open();
    void close();
    bool isOpen() const { return m_dec != nullptr; }

    // samples decoded into pcm (at most maxSamples), or < 0 on error
    int decode(const uint8_t* data, size_t size, int16_t* pcm, int maxSamples);
    // packet loss concealment for one missing frame of `samples` samples
    // (opus_decode with no data); the samples written, or < 0
    int conceal(int16_t* pcm, int samples);

private:
    OpusDecoder* m_dec = nullptr;
};
