/*
 * Mythos Voz: the microphone clean-up of the native engine.
 *
 * The browser asks getUserMedia for WebRTC's noise suppression; the native
 * capture (OpenAL) gave the raw microphone, so fans, hum and keyboard went
 * into every frame. VoiceDenoiser does the same job before Opus:
 *   - a 2nd order high-pass at 80 Hz (hum, desk thumps, mic rumble)
 *   - RNNoise (vendored in rnnoise/), 10 ms steps of 480 samples at 48 kHz
 * process() works in place on a frame (any multiple of 480 samples: the
 * presets have 1920 and 2880) and gives the highest voice probability RNNoise
 * saw in it, which voice activation uses so noise alone does not open it.
 */

#pragma once

#include <cstdint>

struct DenoiseState;

class VoiceDenoiser
{
public:
    static constexpr int kStep = 480; // RNNoise's frame: 10 ms at 48 kHz

    VoiceDenoiser();
    ~VoiceDenoiser();
    VoiceDenoiser(const VoiceDenoiser&) = delete;
    VoiceDenoiser& operator=(const VoiceDenoiser&) = delete;

    // n samples of 48 kHz mono, in place; returns the voice probability
    // (0..1, the highest of its 10 ms steps), or -1 when nothing was done
    float process(int16_t* pcm, int n);

    // a new microphone or a reopened one: the filters start over
    void reset();

private:
    DenoiseState* m_st = nullptr;
    // high-pass biquad state (direct form I)
    float m_x1 = 0, m_x2 = 0, m_y1 = 0, m_y2 = 0;
    float m_buf[kStep];
};
