# RNNoise (vendored)

Noise suppression for the native voice engine (Windows client): the browser
gets WebRTC's noise suppression from getUserMedia, the native capture had
none. Source: https://github.com/xiph/rnnoise tag v0.1.1 (commit
6cbfd53e), BSD license (COPYING). Files copied as they are, only the ones the
library needs (no training scripts, no rnn_reader.c). Two generic global names
are renamed at compile time in src/CMakeLists.txt and the voice harness
(`common`, `compute_rnn`) so nothing can clash with other code.

Local change: the five variable-length arrays of celt_lpc.c and pitch.c go
through RNN_VLA (arch.h), _alloca on MSVC, which has no C99 VLAs.
