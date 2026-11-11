/*
 * Mythos Voz: voice playback through OpenAL, on a device of its own.
 *
 * alcOpenDevice(name or the default) and alcCreateContext(dev,
 * {ALC_FREQUENCY, 48000}), made current only on the voice thread with
 * alcSetThreadContext (ALC_EXT_thread_local_context, which OpenAL Soft has;
 * the function comes from alcGetProcAddress). So it never races the game
 * sound's alcMakeContextCurrent (framework/sound is not changed), it plays
 * while game sound is off, and voice can go to a headset while the game
 * plays on the speakers.
 *
 * One streaming source per speaker (at most 8): AL_SOURCE_RELATIVE at the
 * listener, no distance model; 4 buffers each, refilled as they finish;
 * a source that ran dry is started again by the next queue(). A near
 * speaker with a place (setPan) is moved onto the unit circle in front of
 * the listener, x = pan, z = -sqrt(1 - pan^2) (rolloff 0: no distance
 * attenuation, the gain is ours), and OpenAL Soft pans it for the output
 * (stereo, surround or HRTF). Measured with OpenAL Soft 1.23 on a stereo
 * output: at pan 0 it is the very same as a source at the listener (each side
 * -4.5 dB); the near side follows a constant-power law within 0.5 dB, the far
 * side falls faster (-13 dB at pan 0.5) and is gone from pan 0.87; the total
 * power is 1.5 dB over the centre's at the sides.
 */

#include "audioio.h"

#include <AL/al.h>
#include <AL/alc.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <mutex>
#include <string>
#include <vector>

#ifndef ALC_CONNECTED
#define ALC_CONNECTED 0x313 // ALC_EXT_disconnect
#endif
#ifndef ALC_ALL_DEVICES_SPECIFIER
#define ALC_ALL_DEVICES_SPECIFIER 0x1013 // ALC_ENUMERATE_ALL_EXT
#endif

std::mutex& openalListMutex()
{
    static std::mutex mutex;
    return mutex;
}

namespace
{
    using SetThreadContextFn = ALCboolean(ALC_APIENTRY*)(ALCcontext*);

    constexpr int kStreams = 8;
    constexpr int kBuffers = 4;

    SetThreadContextFn threadContextFn()
    {
        if (alcIsExtensionPresent(nullptr, "ALC_EXT_thread_local_context") != ALC_TRUE)
            return nullptr;
        return reinterpret_cast<SetThreadContextFn>(alcGetProcAddress(nullptr, "alcSetThreadContext"));
    }

    std::vector<std::string> splitList(const ALCchar* list)
    {
        std::vector<std::string> out;
        if (!list)
            return out;
        while (*list && out.size() < 32) {
            std::string name(list);
            list += name.size() + 1;
            if (!name.empty() && std::find(out.begin(), out.end(), name) == out.end())
                out.push_back(std::move(name));
        }
        return out;
    }

    class OpenALPlayback final : public AudioOutput
    {
    public:
        ~OpenALPlayback() override { close(); }

        bool supported() override { return threadContextFn() != nullptr; }

        bool open(const std::string& device) override
        {
            close();
            const SetThreadContextFn setContext = threadContextFn();
            if (!setContext)
                return false;
            ALCdevice* dev = nullptr;
            std::string opened;
            if (!device.empty()) {
                dev = alcOpenDevice(device.c_str());
                if (dev)
                    opened = device;
            }
            if (!dev)
                dev = alcOpenDevice(nullptr);
            if (!dev)
                return false;
            const ALCint attrs[] = { ALC_FREQUENCY, 48000, 0 };
            ALCcontext* ctx = alcCreateContext(dev, attrs);
            if (!ctx) {
                alcCloseDevice(dev);
                return false;
            }
            if (setContext(ctx) != ALC_TRUE) {
                alcDestroyContext(ctx);
                alcCloseDevice(dev);
                return false;
            }
            alGetError();
            alDistanceModel(AL_NONE);
            alListenerf(AL_GAIN, 1.0f);
            m_setContext = setContext;
            m_dev = dev;
            m_ctx = ctx;
            m_name = opened;
            m_canCheck = alcIsExtensionPresent(dev, "ALC_EXT_disconnect") == ALC_TRUE;
            return true;
        }

        void close() override
        {
            if (!m_ctx)
                return;
            m_setContext(m_ctx);
            for (int i = 0; i < kStreams; ++i)
                closeStream(i);
            m_setContext(nullptr);
            alcDestroyContext(m_ctx);
            alcCloseDevice(m_dev);
            m_ctx = nullptr;
            m_dev = nullptr;
            m_name.clear();
        }

        bool isOpen() const override { return m_ctx != nullptr; }
        std::string openedName() const override { return m_name; }

        bool lost() override
        {
            if (!m_dev || !m_canCheck)
                return false;
            ALCint connected = 1;
            alcGetIntegerv(m_dev, ALC_CONNECTED, 1, &connected);
            return connected == 0;
        }

        int openStream() override
        {
            if (!m_ctx)
                return -1;
            for (int i = 0; i < kStreams; ++i) {
                Stream& s = m_streams[i];
                if (s.used)
                    continue;
                alGetError();
                alGenSources(1, &s.source);
                if (alGetError() != AL_NO_ERROR)
                    return -1;
                alGenBuffers(kBuffers, s.buffers.data());
                if (alGetError() != AL_NO_ERROR) {
                    alDeleteSources(1, &s.source);
                    return -1;
                }
                alSourcei(s.source, AL_SOURCE_RELATIVE, AL_TRUE);
                alSource3f(s.source, AL_POSITION, 0.0f, 0.0f, 0.0f);
                alSourcef(s.source, AL_ROLLOFF_FACTOR, 0.0f);
                alSourcef(s.source, AL_GAIN, 1.0f);
                alSourcei(s.source, AL_LOOPING, AL_FALSE);
                s.free.assign(s.buffers.begin(), s.buffers.end());
                s.gain = 1.0f;
                s.placed = false;
                s.pan = 0.0f;
                s.used = true;
                return i;
            }
            return -1;
        }

        void closeStream(const int stream) override
        {
            Stream* s = get(stream);
            if (!s)
                return;
            alSourceStop(s->source);
            alSourcei(s->source, AL_BUFFER, 0);
            alDeleteSources(1, &s->source);
            alDeleteBuffers(kBuffers, s->buffers.data());
            s->free.clear();
            s->used = false;
            alGetError();
        }

        int pending(const int stream) override
        {
            Stream* s = get(stream);
            if (!s)
                return 0;
            ALint processed = 0;
            alGetSourcei(s->source, AL_BUFFERS_PROCESSED, &processed);
            alGetError(); // an error left by an earlier call must not lose a buffer here
            while (processed-- > 0) {
                ALuint b = 0;
                alSourceUnqueueBuffers(s->source, 1, &b);
                if (alGetError() != AL_NO_ERROR || b == 0)
                    break;
                s->free.push_back(b);
            }
            ALint queued = 0;
            alGetSourcei(s->source, AL_BUFFERS_QUEUED, &queued);
            return queued;
        }

        bool canQueue(const int stream) override
        {
            const Stream* s = get(stream);
            return s && !s->free.empty();
        }

        bool queue(const int stream, const int16_t* pcm, const int samples) override
        {
            Stream* s = get(stream);
            if (!s || s->free.empty() || !pcm || samples <= 0)
                return false;
            const ALuint b = s->free.back();
            alGetError();
            alBufferData(b, AL_FORMAT_MONO16, pcm, static_cast<ALsizei>(samples * sizeof(int16_t)), 48000);
            alSourceQueueBuffers(s->source, 1, &b);
            if (alGetError() != AL_NO_ERROR)
                return false;
            s->free.pop_back();
            ALint state = AL_STOPPED;
            alGetSourcei(s->source, AL_SOURCE_STATE, &state);
            if (state != AL_PLAYING)
                alSourcePlay(s->source); // first buffer of a spurt, or ran dry
            alGetError();
            return true;
        }

        void setGain(const int stream, const float gain) override
        {
            Stream* s = get(stream);
            if (!s)
                return;
            const float g = std::clamp(gain, 0.0f, 1.0f);
            if (g != s->gain) {
                s->gain = g;
                alSourcef(s->source, AL_GAIN, g);
            }
        }

        void setPan(const int stream, const bool placed, const float pan) override
        {
            Stream* s = get(stream);
            if (!s)
                return;
            const float p = placed && std::isfinite(pan) ? std::clamp(pan, -1.0f, 1.0f) : 0.0f;
            if (placed == s->placed && p == s->pan)
                return;
            s->placed = placed;
            s->pan = p;
            if (placed)
                alSource3f(s->source, AL_POSITION, p, 0.0f, -std::sqrt((std::max)(0.0f, 1.0f - p * p)));
            else
                alSource3f(s->source, AL_POSITION, 0.0f, 0.0f, 0.0f);
        }

        std::vector<std::string> devices() override
        {
            std::lock_guard<std::mutex> lock(openalListMutex());
            if (alcIsExtensionPresent(nullptr, "ALC_ENUMERATE_ALL_EXT") == ALC_TRUE)
                return splitList(alcGetString(nullptr, ALC_ALL_DEVICES_SPECIFIER));
            return splitList(alcGetString(nullptr, ALC_DEVICE_SPECIFIER));
        }

    private:
        struct Stream
        {
            bool used = false;
            ALuint source = 0;
            std::array<ALuint, kBuffers> buffers{};
            std::vector<ALuint> free;
            float gain = 1.0f;
            bool placed = false; // setPan: on the circle in front, at pan
            float pan = 0.0f;
        };

        Stream* get(const int stream)
        {
            if (!m_ctx || stream < 0 || stream >= kStreams || !m_streams[stream].used)
                return nullptr;
            return &m_streams[stream];
        }

        const Stream* get(const int stream) const
        {
            if (!m_ctx || stream < 0 || stream >= kStreams || !m_streams[stream].used)
                return nullptr;
            return &m_streams[stream];
        }

        SetThreadContextFn m_setContext = nullptr;
        ALCdevice* m_dev = nullptr;
        ALCcontext* m_ctx = nullptr;
        std::string m_name;
        bool m_canCheck = false;
        std::array<Stream, kStreams> m_streams{};
    };
}

std::unique_ptr<AudioOutput> createOpenALPlayback()
{
    return std::make_unique<OpenALPlayback>();
}
