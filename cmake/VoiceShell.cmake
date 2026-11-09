# Mythos Voz: pastes the browser voice engine (browser/voice/mythos-voice.js)
# into a copy of the emscripten shell (browser/shell.html), in place of the
# marker <script>/*MYTHOS_VOICE*/</script>. The engine then ships inside
# index.html: no new file to download, publish or deploy.
#
# The output is rewritten only when its content changes (configure_file), so
# the client relinks only then.
#
# Script mode, for a check without emscripten (browser/voice/test/lint.mjs):
#   cmake -DVOICE_SHELL_IN=browser/shell.html -DVOICE_JS=browser/voice/mythos-voice.js \
#         -DVOICE_SHELL_OUT=/tmp/shell.voice.html -P cmake/VoiceShell.cmake
function(mythos_voice_shell shell_in voice_js shell_out)
  file(READ "${shell_in}" _shell)
  file(READ "${voice_js}" _code)
  set(_marker "<script>/*MYTHOS_VOICE*/</script>")
  string(FIND "${_shell}" "${_marker}" _at)
  if(_at EQUAL -1)
    message(FATAL_ERROR "${shell_in} has no ${_marker} marker for the voice engine")
  endif()
  # emscripten replaces {{{ SCRIPT }}} in the shell and preprocesses it
  string(FIND "${_code}" "{{{" _braces)
  if(NOT _braces EQUAL -1)
    message(FATAL_ERROR "${voice_js} must not contain three braces in a row (the emscripten shell marker)")
  endif()
  string(FIND "${_code}" "</script" _end)
  if(NOT _end EQUAL -1)
    message(FATAL_ERROR "${voice_js} must not contain the end of a script tag")
  endif()
  string(REPLACE "${_marker}" "<script>\n${_code}</script>" _shell "${_shell}")
  file(WRITE "${shell_out}.tmp" "${_shell}")
  configure_file("${shell_out}.tmp" "${shell_out}" COPYONLY)
endfunction()

if(CMAKE_SCRIPT_MODE_FILE AND DEFINED VOICE_SHELL_OUT)
  mythos_voice_shell("${VOICE_SHELL_IN}" "${VOICE_JS}" "${VOICE_SHELL_OUT}")
endif()
