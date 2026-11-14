/*
 * Mythos Voz: microphone clean-up (see voicedsp.h).
 */

#include "voicedsp.h"

#include <algorithm>
#include <cmath>

extern "C" {
#include "rnnoise/rnnoise.h"
}

namespace
{
    // 2nd order Butterworth high-pass, 80 Hz at 48 kHz (RBJ cookbook)
    struct HighPass
    {
        float b0, b1, b2, a1, a2;
        HighPass()
        {
            const double pi = 3.14159265358979323846;
            const double w0 = 2.0 * pi * 80.0 / 48000.0;
            const double q = 0.70710678118654752440;
            const double alpha = std::sin(w0) / (2.0 * q);
            const double c = std::cos(w0);
            const double a0 = 1.0 + alpha;
            b0 = static_cast<float>((1.0 + c) / 2.0 / a0);
            b1 = static_cast<float>(-(1.0 + c) / a0);
            b2 = b0;
            a1 = static_cast<float>(-2.0 * c / a0);
            a2 = static_cast<float>((1.0 - alpha) / a0);
        }
    };
    const HighPass kHp;
}

VoiceDenoiser::VoiceDenoiser() { m_st = rnnoise_create(nullptr); }

VoiceDenoiser::~VoiceDenoiser()
{
    if (m_st)
        rnnoise_destroy(m_st);
}

void VoiceDenoiser::reset()
{
    if (m_st)
        rnnoise_destroy(m_st);
    m_st = rnnoise_create(nullptr);
    m_x1 = m_x2 = m_y1 = m_y2 = 0;
}

float VoiceDenoiser::process(int16_t* pcm, const int n)
{
    if (!m_st || !pcm || n < kStep || n % kStep != 0)
        return -1.0f;
    float best = 0.0f;
    for (int off = 0; off < n; off += kStep) {
        int16_t* s = pcm + off;
        for (int i = 0; i < kStep; ++i) {
            // RNNoise takes floats on the int16 scale
            const float x = static_cast<float>(s[i]);
            const float y = kHp.b0 * x + kHp.b1 * m_x1 + kHp.b2 * m_x2 - kHp.a1 * m_y1 - kHp.a2 * m_y2;
            m_x2 = m_x1;
            m_x1 = x;
            m_y2 = m_y1;
            m_y1 = std::isfinite(y) ? y : 0.0f;
            m_buf[i] = m_y1;
        }
        const float p = rnnoise_process_frame(m_st, m_buf, m_buf);
        best = (std::max)(best, p);
        for (int i = 0; i < kStep; ++i) {
            const float v = std::isfinite(m_buf[i]) ? m_buf[i] : 0.0f;
            s[i] = static_cast<int16_t>(std::lround(std::clamp(v, -32768.0f, 32767.0f)));
        }
    }
    return best;
}
