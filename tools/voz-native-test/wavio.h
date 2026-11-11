// Mythos Voz harness: WAV files in and out, and RMS envelopes.
//
// readWav takes RIFF/WAVE PCM 16-bit or IEEE float 32-bit, plain or
// WAVE_FORMAT_EXTENSIBLE (what OpenAL Soft's wave backend writes), any
// channel count (channel 0 is kept) and any rate (linear resampling to
// 48 kHz). A data chunk whose size was never written (0 or 0xFFFFFFFF, a
// writer that did not close) is read to the end of the file.
#pragma once

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace wavio
{
    struct Audio
    {
        int rate = 48000;
        int channels = 1;
        std::vector<int16_t> pcm; // mono, 48 kHz
    };

    inline uint32_t le32(const uint8_t* p) { return p[0] | (p[1] << 8) | (p[2] << 16) | (static_cast<uint32_t>(p[3]) << 24); }
    inline uint16_t le16(const uint8_t* p) { return static_cast<uint16_t>(p[0] | (p[1] << 8)); }

    inline bool readWav(const std::string& path, Audio& out, std::string& err)
    {
        FILE* f = std::fopen(path.c_str(), "rb");
        if (!f) {
            err = "cannot open " + path;
            return false;
        }
        std::vector<uint8_t> b;
        uint8_t chunk[65536];
        size_t n;
        while ((n = std::fread(chunk, 1, sizeof(chunk), f)) > 0)
            b.insert(b.end(), chunk, chunk + n);
        std::fclose(f);
        if (b.size() < 12 || std::memcmp(b.data(), "RIFF", 4) != 0 || std::memcmp(b.data() + 8, "WAVE", 4) != 0) {
            err = "not a WAV file";
            return false;
        }
        int format = 0, channels = 0, rate = 0, bits = 0;
        size_t at = 12;
        const uint8_t* data = nullptr;
        size_t dataLen = 0;
        while (at + 8 <= b.size()) {
            const uint8_t* c = b.data() + at;
            uint32_t len = le32(c + 4);
            if (std::memcmp(c, "fmt ", 4) == 0 && at + 8 + 16 <= b.size()) {
                format = le16(c + 8);
                channels = le16(c + 10);
                rate = static_cast<int>(le32(c + 12));
                bits = le16(c + 22);
                if (format == 0xFFFE && len >= 40 && at + 8 + 26 <= b.size())
                    format = le16(c + 8 + 24); // the sub-format GUID starts with the tag
            } else if (std::memcmp(c, "data", 4) == 0) {
                data = c + 8;
                const size_t left = b.size() - at - 8;
                dataLen = (len == 0 || len == 0xFFFFFFFFu || len > left) ? left : len;
                break;
            }
            at += 8 + len + (len & 1);
        }
        if (!data || channels < 1 || rate < 1000 || !((format == 1 && bits == 16) || (format == 3 && bits == 32))) {
            err = "unsupported WAV (need PCM16 or float32)";
            return false;
        }
        const size_t frameBytes = static_cast<size_t>(channels) * (bits / 8);
        const size_t frames = dataLen / frameBytes;
        std::vector<float> mono(frames);
        for (size_t i = 0; i < frames; ++i) {
            const uint8_t* p = data + i * frameBytes;
            if (format == 1) {
                mono[i] = static_cast<int16_t>(le16(p)) / 32768.0f;
            } else {
                float v;
                std::memcpy(&v, p, 4);
                mono[i] = v;
            }
        }
        out.rate = rate;
        out.channels = channels;
        out.pcm.clear();
        if (rate == 48000) {
            out.pcm.reserve(frames);
            for (const float v : mono)
                out.pcm.push_back(static_cast<int16_t>(std::lrint(std::fmax(-32768.0f, std::fmin(32767.0f, v * 32768.0f)))));
        } else {
            const double step = static_cast<double>(rate) / 48000.0;
            for (double pos = 0; pos + 1 < static_cast<double>(frames); pos += step) {
                const size_t k = static_cast<size_t>(pos);
                const double fr = pos - k;
                const double v = mono[k] + (mono[k + 1] - mono[k]) * fr;
                out.pcm.push_back(static_cast<int16_t>(std::lrint(std::fmax(-32768.0, std::fmin(32767.0, v * 32768.0)))));
            }
        }
        return true;
    }

    inline bool writeWav(const std::string& path, const std::vector<int16_t>& pcm, const int rate = 48000)
    {
        FILE* f = std::fopen(path.c_str(), "wb");
        if (!f)
            return false;
        const uint32_t dataLen = static_cast<uint32_t>(pcm.size() * 2);
        uint8_t h[44];
        auto put32 = [&](int at, uint32_t v) {
            h[at] = v & 255;
            h[at + 1] = (v >> 8) & 255;
            h[at + 2] = (v >> 16) & 255;
            h[at + 3] = (v >> 24) & 255;
        };
        auto put16 = [&](int at, uint16_t v) {
            h[at] = v & 255;
            h[at + 1] = (v >> 8) & 255;
        };
        std::memcpy(h, "RIFF", 4);
        put32(4, 36 + dataLen);
        std::memcpy(h + 8, "WAVEfmt ", 8);
        put32(16, 16);
        put16(20, 1);
        put16(22, 1);
        put32(24, static_cast<uint32_t>(rate));
        put32(28, static_cast<uint32_t>(rate * 2));
        put16(32, 2);
        put16(34, 16);
        std::memcpy(h + 36, "data", 4);
        put32(40, dataLen);
        bool ok = std::fwrite(h, 1, 44, f) == 44;
        if (!pcm.empty())
            ok = ok && std::fwrite(pcm.data(), 2, pcm.size(), f) == pcm.size();
        return std::fclose(f) == 0 && ok;
    }

    // dBFS per window (4800 samples = 100 ms)
    inline std::vector<double> envelope(const std::vector<int16_t>& pcm, const size_t win = 4800)
    {
        std::vector<double> out;
        for (size_t i = 0; i + win <= pcm.size(); i += win) {
            double s = 0;
            for (size_t k = 0; k < win; ++k) {
                const double x = pcm[i + k] / 32768.0;
                s += x * x;
            }
            out.push_back(10.0 * std::log10(s / win + 1e-12));
        }
        return out;
    }
}
