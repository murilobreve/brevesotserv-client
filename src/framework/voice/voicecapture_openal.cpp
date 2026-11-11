/*
 * Mythos Voz: the microphone through OpenAL capture.
 *
 * alcCaptureOpenDevice(name or the default, 48000, AL_FORMAT_MONO16, 9600):
 * a 200 ms ring, which absorbs the voice thread's timer jitter (Windows
 * timers tick every 15.6 ms unless someone raised the resolution). The
 * capture device is independent of any context, so game sound (SoundManager)
 * is not involved. Every call is on the voice thread, except devices().
 */

#include "audioio.h"

#include <AL/al.h>
#include <AL/alc.h>

#include <algorithm>

#ifndef ALC_CONNECTED
#define ALC_CONNECTED 0x313 // ALC_EXT_disconnect
#endif

namespace
{
    std::vector<std::string> splitDeviceList(const ALCchar* list)
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

    class OpenALCapture final : public AudioInput
    {
    public:
        ~OpenALCapture() override { close(); }

        bool open(const std::string& device, const int rate) override
        {
            close();
            const ALCsizei ring = static_cast<ALCsizei>(rate / 5); // 200 ms
            ALCdevice* dev = nullptr;
            std::string opened;
            if (!device.empty()) {
                dev = alcCaptureOpenDevice(device.c_str(), static_cast<ALCuint>(rate), AL_FORMAT_MONO16, ring);
                if (dev)
                    opened = device;
            }
            if (!dev)
                dev = alcCaptureOpenDevice(nullptr, static_cast<ALCuint>(rate), AL_FORMAT_MONO16, ring);
            if (!dev)
                return false;
            alcGetError(dev);
            alcCaptureStart(dev);
            if (alcGetError(dev) != ALC_NO_ERROR) {
                alcCaptureCloseDevice(dev);
                return false;
            }
            m_dev = dev;
            m_name = opened;
            m_canCheck = alcIsExtensionPresent(dev, "ALC_EXT_disconnect") == ALC_TRUE;
            return true;
        }

        void close() override
        {
            if (!m_dev)
                return;
            alcCaptureStop(m_dev);
            alcCaptureCloseDevice(m_dev);
            m_dev = nullptr;
            m_name.clear();
        }

        bool isOpen() const override { return m_dev != nullptr; }
        std::string openedName() const override { return m_name; }

        bool lost() override
        {
            if (!m_dev || !m_canCheck)
                return false;
            ALCint connected = 1;
            alcGetIntegerv(m_dev, ALC_CONNECTED, 1, &connected);
            return connected == 0;
        }

        int available() override
        {
            if (!m_dev)
                return 0;
            ALCint n = 0;
            alcGetIntegerv(m_dev, ALC_CAPTURE_SAMPLES, 1, &n);
            return n > 0 ? n : 0;
        }

        int read(int16_t* out, const int samples) override
        {
            const int n = (std::min)(samples, available());
            if (n <= 0)
                return 0;
            alcCaptureSamples(m_dev, out, n);
            return n;
        }

        std::vector<std::string> devices() override
        {
            std::lock_guard<std::mutex> lock(openalListMutex());
            return splitDeviceList(alcGetString(nullptr, ALC_CAPTURE_DEVICE_SPECIFIER));
        }

    private:
        ALCdevice* m_dev = nullptr;
        std::string m_name;
        bool m_canCheck = false;
    };
}

std::unique_ptr<AudioInput> createOpenALCapture()
{
    return std::make_unique<OpenALCapture>();
}
