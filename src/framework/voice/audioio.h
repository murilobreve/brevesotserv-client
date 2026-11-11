/*
 * Mythos Voz: the audio devices of the native engine, as interfaces, so the
 * Linux harness (tools/voz-native-test) can put a WAV file in place of the
 * microphone or of the speakers.
 *
 * Every call happens on the engine's voice thread, except devices() and
 * supported(), which may be called from any thread.
 *
 * Audio is 48 kHz mono 16-bit throughout.
 */

#pragma once

#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

class AudioInput
{
public:
    virtual ~AudioInput() = default;

    // device "" = the system default; a name that is not there opens the
    // default instead (openedName() then differs from the name asked for)
    virtual bool open(const std::string& device, int rate) = 0;
    virtual void close() = 0;
    virtual bool isOpen() const = 0;
    virtual std::string openedName() const = 0;
    // the device went away (unplugged)
    virtual bool lost() = 0;
    // samples ready to read
    virtual int available() = 0;
    virtual int read(int16_t* out, int samples) = 0;

    virtual std::vector<std::string> devices() = 0;
};

class AudioOutput
{
public:
    virtual ~AudioOutput() = default;

    // whether this machine can play at all (checked once, opens nothing)
    virtual bool supported() = 0;

    virtual bool open(const std::string& device) = 0;
    virtual void close() = 0;
    virtual bool isOpen() const = 0;
    virtual std::string openedName() const = 0;
    virtual bool lost() = 0;

    // one stream per speaker; -1 when none is left
    virtual int openStream() = 0;
    virtual void closeStream(int stream) = 0;
    // takes back the buffers that finished playing; returns how many are
    // still queued (playing or waiting)
    virtual int pending(int stream) = 0;
    // whether one more buffer can be queued
    virtual bool canQueue(int stream) = 0;
    // queues one buffer and (re)starts the stream if it was not playing
    virtual bool queue(int stream, const int16_t* pcm, int samples) = 0;
    virtual void setGain(int stream, float gain) = 0; // 0-1

    virtual std::vector<std::string> devices() = 0;
};

// voicecapture_openal.cpp, voiceplayback_openal.cpp
std::unique_ptr<AudioInput> createOpenALCapture();
std::unique_ptr<AudioOutput> createOpenALPlayback();

// OpenAL keeps the device lists it returns in shared strings: every listing
// (capture and playback, any thread) holds this lock
std::mutex& openalListMutex();
