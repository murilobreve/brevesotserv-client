# Mythos Voz: Linux harness for the native voice engine.
#
# Builds the engine's own files (src/framework/voice: codec, jitter buffer,
# OpenAL capture and playback, NativeVoiceEngine) with -DVOICE_STANDALONE,
# so nothing of the framework comes in, against the system's libopus and
# OpenAL Soft (pkg-config opus openal) and ixwebsocket built from source at
# the version of the client's vcpkg baseline (v12.0.0), with TLS through
# OpenSSL.
#
#   cmake -S tools/voz-native-test -B /tmp/voz-native -G Ninja
#   cmake --build /tmp/voz-native
#
# Options:
#   VOZ_SANITIZE (ON)        -fsanitize=address,undefined on everything
#   IXWEBSOCKET_SOURCE_DIR   a local clone of IXWebSocket (else FetchContent
#                            clones https://github.com/machinezone/IXWebSocket
#                            at v12.0.0)
cmake_minimum_required(VERSION 3.20)
project(voz_native_test LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE RelWithDebInfo)
endif()

option(VOZ_SANITIZE "AddressSanitizer and UndefinedBehaviorSanitizer" ON)
set(IXWEBSOCKET_SOURCE_DIR "" CACHE PATH "Local IXWebSocket checkout (v12.0.0)")

if(VOZ_SANITIZE)
  # before ixwebsocket, so it is instrumented too
  add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer -fno-sanitize-recover=undefined)
  add_link_options(-fsanitize=address,undefined)
endif()

find_package(PkgConfig REQUIRED)
pkg_check_modules(OPUS REQUIRED IMPORTED_TARGET opus)
pkg_check_modules(OPENAL REQUIRED IMPORTED_TARGET openal)
find_package(Threads REQUIRED)
find_package(nlohmann_json 3 REQUIRED)

# ixwebsocket at the vcpkg baseline's version (ports/ixwebsocket: 12.0.0)
set(USE_TLS ON CACHE BOOL "" FORCE)
set(USE_OPEN_SSL ON CACHE BOOL "" FORCE)
set(IXWEBSOCKET_INSTALL OFF CACHE BOOL "" FORCE)
if(IXWEBSOCKET_SOURCE_DIR)
  add_subdirectory(${IXWEBSOCKET_SOURCE_DIR} ${CMAKE_BINARY_DIR}/ixwebsocket EXCLUDE_FROM_ALL)
else()
  include(FetchContent)
  FetchContent_Declare(ixwebsocket
    GIT_REPOSITORY https://github.com/machinezone/IXWebSocket
    GIT_TAG v12.0.0
    GIT_SHALLOW TRUE)
  FetchContent_MakeAvailable(ixwebsocket)
endif()

set(VOICE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../src/framework/voice)
set(VOICE_ENGINE_SOURCES
  ${VOICE_DIR}/voicecodec.cpp
  ${VOICE_DIR}/jitterbuffer.cpp
  ${VOICE_DIR}/voicecapture_openal.cpp
  ${VOICE_DIR}/voiceplayback_openal.cpp
  ${VOICE_DIR}/voiceengine_native.cpp
)

add_executable(voz-native-test main.cpp ${VOICE_ENGINE_SOURCES})
target_compile_definitions(voz-native-test PRIVATE VOICE_STANDALONE)
target_include_directories(voz-native-test PRIVATE ${VOICE_DIR} ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_options(voz-native-test PRIVATE -Wall -Wextra -Wno-unused-parameter)
target_link_libraries(voz-native-test PRIVATE PkgConfig::OPUS PkgConfig::OPENAL ixwebsocket nlohmann_json::nlohmann_json Threads::Threads)
