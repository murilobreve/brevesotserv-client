/*
 * Mythos Voz: the engine of a build without audio. isSupported() is false,
 * so modules/game_voice uses its presence-only (lite) engine; every call is
 * a no-op. A desktop build with voice on but VOICE_NATIVE off (no libopus)
 * uses it.
 */

#include "voiceengine.h"

namespace
{
    class NullVoiceEngine final : public VoiceEngine
    {
    public:
        bool isSupported() override { return false; }
        void connect(const std::string&, const std::string&, const std::string&, const std::string&) override {}
        void disconnect() override {}
        void sendControl(const std::string&) override {}
        void setTransmit(int) override {}
        void setMode(bool) override {}
        void setVadThreshold(float) override {}
        void setPreset(int) override {}
        void setInputDevice(const std::string&) override {}
        void setOutputDevice(const std::string&) override {}
        std::vector<std::string> getInputDevices() override { return {}; }
        std::vector<std::string> getOutputDevices() override { return {}; }
        void setInputGain(float) override {}
        void setOutputVolume(float) override {}
        void setUserVolume(int, float) override {}
        void setSlotVolume(int, float) override {}
        void setUserSpatial(int, float, float) override {}
        void setDeafened(bool) override {}
        void setSelfMuted(bool) override {}
        void setMeter(bool) override {}
        void setPttMouse(int, int) override {}
        void setGlobalPtt(int) override {}
        void startLocalTest(bool) override {}
        void requestStats() override {}
        void terminate() override {}
    };
}

std::unique_ptr<VoiceEngine> createVoiceEngine(VoiceEngine::Sink)
{
    return std::make_unique<NullVoiceEngine>();
}
