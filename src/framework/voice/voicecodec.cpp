/*
 * Mythos Voz: libopus wrappers (see voicecodec.h).
 */

#include "voicecodec.h"

#include <opus.h>

namespace voicecodec
{
    namespace
    {
        const Preset kPresets[3] = {
            { 16000, 1920, OPUS_BANDWIDTH_WIDEBAND },
            { 12000, 2880, OPUS_BANDWIDTH_WIDEBAND },
            { 24000, 1920, OPUS_BANDWIDTH_SUPERWIDEBAND },
        };
    }

    const Preset& preset(const int index)
    {
        return kPresets[index >= 0 && index <= 2 ? index : 0];
    }

    int packetSamples(const uint8_t* data, const size_t size)
    {
        if (!data || size < 1 || size > 1275)
            return OPUS_BAD_ARG;
        return opus_packet_get_nb_samples(data, static_cast<opus_int32>(size), kRate);
    }
}

OpusEnc::~OpusEnc() { close(); }

bool OpusEnc::open(const int index)
{
    close();
    const auto& p = voicecodec::preset(index);
    int err = OPUS_OK;
    OpusEncoder* enc = opus_encoder_create(voicecodec::kRate, 1, OPUS_APPLICATION_VOIP, &err);
    if (!enc || err != OPUS_OK) {
        if (enc)
            opus_encoder_destroy(enc);
        return false;
    }
    opus_encoder_ctl(enc, OPUS_SET_BITRATE(p.bitrate));
    opus_encoder_ctl(enc, OPUS_SET_VBR(1));
    opus_encoder_ctl(enc, OPUS_SET_VBR_CONSTRAINT(1)); // constrained VBR
    opus_encoder_ctl(enc, OPUS_SET_COMPLEXITY(5));
    opus_encoder_ctl(enc, OPUS_SET_SIGNAL(OPUS_SIGNAL_VOICE));
    opus_encoder_ctl(enc, OPUS_SET_INBAND_FEC(0));
    opus_encoder_ctl(enc, OPUS_SET_DTX(0));
    opus_encoder_ctl(enc, OPUS_SET_PACKET_LOSS_PERC(0));
    opus_encoder_ctl(enc, OPUS_SET_MAX_BANDWIDTH(p.maxBandwidth));
    m_enc = enc;
    m_preset = index >= 0 && index <= 2 ? index : 0;
    m_frameSamples = p.frameSamples;
    return true;
}

void OpusEnc::close()
{
    if (m_enc) {
        opus_encoder_destroy(m_enc);
        m_enc = nullptr;
    }
    m_preset = -1;
    m_frameSamples = 0;
}

int OpusEnc::encode(const int16_t* pcm, uint8_t* out, const int maxBytes)
{
    if (!m_enc || !pcm || !out || maxBytes < 1)
        return OPUS_BAD_ARG;
    return opus_encode(m_enc, pcm, m_frameSamples, out, maxBytes);
}

OpusDec::~OpusDec() { close(); }

bool OpusDec::open()
{
    close();
    int err = OPUS_OK;
    OpusDecoder* dec = opus_decoder_create(voicecodec::kRate, 1, &err);
    if (!dec || err != OPUS_OK) {
        if (dec)
            opus_decoder_destroy(dec);
        return false;
    }
    m_dec = dec;
    return true;
}

void OpusDec::close()
{
    if (m_dec) {
        opus_decoder_destroy(m_dec);
        m_dec = nullptr;
    }
}

int OpusDec::decode(const uint8_t* data, const size_t size, int16_t* pcm, const int maxSamples)
{
    if (!m_dec || !data || size < 1 || !pcm || maxSamples < 1)
        return OPUS_BAD_ARG;
    return opus_decode(m_dec, data, static_cast<opus_int32>(size), pcm, maxSamples, 0);
}

int OpusDec::conceal(int16_t* pcm, const int samples)
{
    if (!m_dec || !pcm || samples < 1)
        return OPUS_BAD_ARG;
    // a frame size that is not a multiple of 2.5 ms would be refused
    return opus_decode(m_dec, nullptr, 0, pcm, samples, 0);
}
