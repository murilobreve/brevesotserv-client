/*
 * Mythos Voz: the browser voice engine (window.MythosVoice).
 *
 * The game (C++ on a pthread) sends JSON commands with MythosVoice.cmd(text)
 * (voiceengine_web.cpp, MAIN_THREAD_ASYNC_EM_ASM); events go back in batches,
 * once per microtask, to Module._otc_voice_event (or to a sink set with
 * MythosVoice.setSink, the test page). Nothing exists until the first command
 * that needs it: no AudioContext, no microphone and no socket.
 *
 * Capture: microphone -> 'mv-capture' worklet (frames of 40 or 60 ms at
 * 48 kHz, the push-to-talk / voice-activation gate) -> AudioEncoder (Opus) ->
 * WebSocket [0x01][flags][seq][opus]. Playback: WebSocket -> one AudioDecoder
 * per speaker -> 'mv-mixer' worklet (jitter buffer per speaker, gains, the
 * place of a proximity voice in the stereo field, limiter) -> speakers. Wire
 * format and jitter policy: protocol C, D, E and I of the voice plan (tools/voz
 * in the server repository). Room slots: 0 party, 1 guild/officers, 2
 * public/stage/echo, 3 near (proximity, "Perto de voce").
 *
 * This file is pasted into index.html by src/CMakeLists.txt, inside the
 * emscripten shell, so it must never hold three braces in a row, the end of a
 * script tag, or a line that starts with a hash sign (emscripten preprocesses
 * the shell). browser/voice/test/lint.mjs checks that.
 */
(function () {
  'use strict';
  if (window.MythosVoice) {
    return;
  }

  var VERSION = 1;
  var RATE = 48000;
  var PRESETS = [
    { bitrate: 16000, frame: 1920 }, // normal: 16 kbps, 40 ms
    { bitrate: 12000, frame: 2880 }, // eco: 12 kbps, 60 ms
    { bitrate: 24000, frame: 1920 } // high: 24 kbps, 40 ms
  ];
  var MAX_OPUS = 240;
  var SPEECH_MIN = 10; // payloads over this are speech (speaking edges)
  var SPK_GAP_MS = 300; // no frame for this long: speaking off
  var MAX_DECODERS = 8;
  var DECODER_IDLE_MS = 10000;
  var MIC_IDLE_MS = 300000; // push-to-talk: the track stops after 5 min unused
  var MIC_IDLE_OFF_MS = 30000; // ... and 30 s once not connected for 30 s (voice off, gave up)
  var MIC_RETRY_MS = 5000; // after a refusal, no new request before this
  var NODEV_RETRY_MS = 15000; // no microphone (or busy): voice activation tries again
  var MOUSE_TX_MAX_MS = 60000; // the side mouse button held longer: released
  var IDLE_SUSPEND_MS = 15000; // nothing to play or capture: the context sleeps
  var AUDIO_IDLE_CLOSE_MS = 30000; // not connected and nothing open: closed
  var SEND_BACKLOG = 16384; // bytes waiting in the socket: audio is dropped
  // the local microphone test plays as this speaker: outside the relay's
  // sids (1..65535, u16 on the wire), so no real speaker can ever share it
  var TEST_SID = 65536;
  var ENC_COOL_MS = 2000; // an encoder that failed: no new one before this
  var WAKE_CHECK_MS = 2000; // a resume() not running by then waits for a press
  var MAX_QUEUED_EVENTS = 512; // events the game has not taken: then compacted
  var STALL_RETRY_MS = 250; // the game's inbox was full: the next try

  // AudioWorklet module: both processors, loaded from a Blob URL. Written as a
  // function only so it can be read and checked here; it runs in the audio
  // thread and sees nothing of this file.
  function workletModule() {
    var IN = 48000; // the rate frames travel at
    var ONSET_DB = -30; // probe (tests): the first block over this after 300 ms below it

    function dbOf(sum, n) {
      return 10 * Math.log10(sum / Math.max(1, n) + 1e-12);
    }

    // microphone -> 48 kHz frames, the gate, the level meter
    class MvCapture extends AudioWorkletProcessor {
      constructor() {
        super();
        this.c = { tx: -1, vad: false, vadDb: -45, gain: 1, muted: false, test: false, meter: false, frame: 1920, vadSlot: 0, probe: false };
        this.frame = 1920;
        this.buf = new Float32Array(this.frame);
        this.fill = 0;
        this.prev = null; // the last frame not sent: voice-activation pre-roll
        this.open = false; // the network gate
        this.slot = 0;
        this.vad = 0;
        this.vadOn = false;
        this.hang = 0;
        this.step = IN / sampleRate; // input samples per 48 kHz sample
        this.frac = 0;
        this.last = 0;
        this.lsum = 0;
        this.ln = 0;
        this.quiet = 0;
        this.alive = true;
        var self = this;
        this.port.onmessage = function (e) {
          var m = e.data;
          if (m.t === 'cfg') {
            self.c = m;
            // a new frame size waits for the end of the spurt, unless the
            // encoder cannot take the old one (now)
            if (m.frame !== self.frame && (!self.open || m.now)) {
              self.resize(m.frame);
            }
          } else if (m.t === 'stop') {
            self.alive = false;
          }
        };
      }

      // a new frame size (preset)
      resize(n) {
        this.frame = n;
        this.buf = new Float32Array(n);
        this.fill = 0;
        this.prev = null;
      }

      busy() {
        var c = this.c;
        return this.open || c.tx >= 0 || (c.vad && !c.muted) || c.test || c.meter || c.probe;
      }

      process(inputs) {
        if (!this.alive) {
          return false;
        }
        var ch = inputs[0] && inputs[0][0];
        if (!ch || !this.busy()) {
          this.fill = 0;
          return true;
        }
        var g = this.c.gain;
        var n = ch.length;
        var i, x;
        if (this.c.probe) {
          var s = 0;
          for (i = 0; i < n; i++) {
            s += ch[i] * ch[i];
          }
          if (dbOf(s, n) > ONSET_DB) {
            if (this.quiet >= 0.3 * sampleRate) {
              this.port.postMessage({ t: 'o' });
            }
            this.quiet = 0;
          } else {
            this.quiet += n;
          }
        }
        if (this.step === 1) {
          for (i = 0; i < n; i++) {
            this.put(ch[i] * g);
          }
        } else {
          // another context rate (Firefox): linear interpolation to 48 kHz
          var inv = 1 / this.step;
          for (i = 0; i < n; i++) {
            x = ch[i] * g;
            while (this.frac < 1) {
              this.put(this.last + (x - this.last) * this.frac);
              this.frac += inv;
            }
            this.frac -= 1;
            this.last = x;
          }
        }
        return true;
      }

      put(x) {
        if (this.c.meter) {
          this.lsum += x * x;
          if (++this.ln >= 4800) {
            this.port.postMessage({ t: 'l', db: dbOf(this.lsum, this.ln) });
            this.lsum = 0;
            this.ln = 0;
          }
        }
        this.buf[this.fill++] = x;
        if (this.fill >= this.frame) {
          this.fill = 0;
          this.onFrame();
        }
      }

      post(pcm, net, end, slot, vad, first) {
        this.port.postMessage({ t: 'f', pcm: pcm, net: net, end: end, slot: slot, vad: vad, first: first }, [pcm.buffer]);
      }

      onFrame() {
        var c = this.c;
        var buf = this.buf;
        var n = this.frame;
        var sum = 0;
        for (var i = 0; i < n; i++) {
          sum += buf[i] * buf[i];
        }
        var db = dbOf(sum, n);
        var hang = Math.max(1, Math.round(300 * IN / n / 1000));
        if (c.vad && !c.muted) {
          if (db >= c.vadDb) {
            this.vadOn = true;
            this.hang = hang;
          } else if (this.vadOn) {
            if (db >= c.vadDb - 6) {
              this.hang = hang;
            } else if (--this.hang <= 0) {
              this.vadOn = false;
            }
          }
        } else {
          this.vadOn = false;
        }
        var want = !c.muted && (c.tx >= 0 || this.vadOn);
        var slot = c.tx >= 0 ? c.tx : c.vadSlot;
        var vad = this.open ? this.vad : (c.tx >= 0 ? 0 : 1); // the spurt's mode, END included
        var sent = false;
        if (want && !this.open) {
          this.open = true;
          this.slot = slot;
          this.vad = vad;
          this.port.postMessage({ t: 'g', on: 1, slot: slot });
          if (vad && this.prev && this.prev.length === n) {
            this.post(this.prev, 1, 0, slot, vad, 1);
            this.prev = null;
            this.post(buf, 1, 0, slot, vad, 0);
          } else {
            this.post(buf, 1, 0, slot, vad, 1);
          }
          sent = true;
        } else if (this.open) {
          var closing = !want || slot !== this.slot;
          this.post(buf, 1, closing ? 1 : 0, this.slot, vad, 0);
          sent = true;
          if (closing) {
            this.open = false;
            this.port.postMessage({ t: 'g', on: 0 });
          }
        } else if (c.test) {
          this.post(buf, 0, 0, 2, 0, 0);
          sent = true;
        }
        if (!this.open && c.frame !== this.frame) {
          this.resize(c.frame);
          return;
        }
        if (sent) {
          this.buf = new Float32Array(n);
        } else {
          var keep = this.prev;
          this.prev = buf;
          this.buf = keep && keep.length === n ? keep : new Float32Array(n);
        }
      }
    }

    // per-speaker jitter buffers (protocol I), gains, the limiter. Stereo
    // out: every voice is centred (left = right, as the mono mix it was),
    // except a speaker's frames on slot 3 (near) once the game gave that
    // speaker a place (spatial: gain 0-1, pan -1 left .. 1 right).
    class MvMixer extends AudioWorkletProcessor {
      constructor() {
        super();
        this.sp = new Map();
        this.users = new Map();
        // sid -> left/right gains of its slot-3 frames: target (tl, tr),
        // current (cl, cr), per-sample step (dl, dr) for n more samples
        this.spatial = new Map();
        this.ramp = Math.max(1, Math.round(0.05 * sampleRate)); // 50 ms
        this.sd = null; // one block of right - left of the voices with a place
        this.slots = [1, 1, 1, 1];
        this.master = 1;
        this.deaf = false;
        this.probe = false;
        this.step = IN / sampleRate;
        this.ms = IN / 1000; // samples per ms at 48 kHz
        this.st = { late: 0, conceal: 0, trimmed: 0, played: 0, spurts: 0, dup: 0, resets: 0 };
        this.psum = 0;
        this.psumR = 0;
        this.pn = 0;
        this.peak = 0;
        this.quiet = 0;
        this.tick = 0;
        var self = this;
        this.port.onmessage = function (e) {
          self.onMsg(e.data);
        };
      }

      clock() {
        // currentFrame is in context samples; jitter math is in 48 kHz samples
        return currentFrame * this.step;
      }

      onMsg(m) {
        if (m.t === 'p') {
          this.onPcm(m);
        } else if (m.t === 'cfg') {
          this.slots = m.slots;
          this.master = m.master;
          this.deaf = m.deaf;
          this.probe = m.probe;
        } else if (m.t === 'u') {
          if (m.x === 1) {
            this.users.delete(m.sid);
          } else {
            this.users.set(m.sid, m.x);
          }
        } else if (m.t === 'sp') {
          this.place(m.sid, m.g, m.p);
        } else if (m.t === 'drop') {
          this.sp.delete(m.sid);
        } else if (m.t === 'reset') {
          this.sp.clear();
          this.users.clear();
          this.spatial.clear();
        } else if (m.t === 's') {
          var st = this.st;
          var out = { t: 's', late: st.late, conceal: st.conceal, trimmed: st.trimmed, played: st.played, spurts: st.spurts, dup: st.dup, resets: st.resets, speakers: this.sp.size, spatial: this.spatial.size, targets: {} };
          this.sp.forEach(function (s, sid) {
            out.targets[sid] = Math.round(s.target / 48);
          });
          if (this.pn > 0) {
            out.rms = dbOf(this.psum, this.pn); // the left channel (both, for a centred voice)
            out.rmsR = dbOf(this.psumR, this.pn);
            out.peak = this.peak;
            this.psum = 0;
            this.psumR = 0;
            this.pn = 0;
            this.peak = 0;
          }
          this.port.postMessage(out);
        }
      }

      // A speaker's place for its slot-3 frames (gain 0-1, pan -1..1, the
      // page clamps them): constant power, scaled so the centre at gain 1 is
      // exactly a centred voice (left = right = 1). Playing on slot 3 now:
      // there in 50 ms; otherwise its next slot-3 frame starts there.
      place(sid, g, p) {
        var a = (p + 1) * Math.PI / 4;
        var tl = g * Math.SQRT2 * Math.cos(a);
        var tr = g * Math.SQRT2 * Math.sin(a);
        var z = this.spatial.get(sid);
        if (!z) {
          z = { tl: 1, tr: 1, cl: 1, cr: 1, dl: 0, dr: 0, n: 0 };
          this.spatial.set(sid, z);
        }
        z.tl = tl;
        z.tr = tr;
        var s = this.sp.get(sid);
        if (s && s.state === 2 && s.slot === 3) {
          z.n = this.ramp;
          z.dl = (tl - z.cl) / z.n;
          z.dr = (tr - z.cr) / z.n;
        } else {
          z.cl = tl;
          z.cr = tr;
          z.n = 0;
        }
      }

      speaker(sid) {
        var s = this.sp.get(sid);
        if (!s) {
          s = { frames: new Array(256), count: 0, buffered: 0, state: 0, next: 0, cur: null, pos: 0, last: null, miss: 0, endAfter: false, hasEnd: false, firstAt: 0, lastAt: 0, prevSeq: -1, prevAt: 0, j: 0, target: 80 * this.ms, slot: 0, len: 1920 };
          this.sp.set(sid, s);
        }
        return s;
      }

      reset(s) {
        for (var i = 0; i < 256; i++) {
          s.frames[i] = null;
        }
        s.count = 0;
        s.buffered = 0;
        s.state = 0;
        s.cur = null;
        s.last = null; // a new spurt never conceals with the old one's tail
        s.pos = 0;
        s.miss = 0;
        s.endAfter = false;
        s.hasEnd = false;
        s.prevSeq = -1;
      }

      onPcm(m) {
        var now = this.clock();
        var s = this.speaker(m.sid);
        var len = m.pcm.length;
        if (s.state === 0) {
          s.state = 1; // buffering
          s.next = m.seq;
          s.firstAt = now;
          this.st.spurts++;
        } else {
          var d = ((m.seq - s.next + 384) & 255) - 128; // modulo 256, -128..127
          if (d < 0) {
            this.st.late++;
            return;
          }
          if (d > 32) {
            // far ahead: a new talk spurt after a gap we did not see end
            this.st.resets++;
            this.reset(s);
            s.state = 1;
            s.next = m.seq;
            s.firstAt = now;
          }
        }
        // J: moving average (1/16) of |arrival interval - frame duration|
        if (s.prevSeq >= 0 && now > s.prevAt) {
          var k = (m.seq - s.prevSeq) & 255;
          if (k >= 1 && k <= 4) {
            s.j += (Math.abs(now - s.prevAt - k * len) - s.j) / 16;
          }
        }
        s.prevSeq = m.seq;
        s.prevAt = now;
        s.lastAt = now;
        s.target = Math.min(240 * this.ms, Math.max(80 * this.ms, 80 * this.ms + 2 * s.j));
        if (s.frames[m.seq]) {
          this.st.dup++;
          return;
        }
        // each frame keeps its slot: the gains follow the frame being played
        s.frames[m.seq] = { pcm: m.pcm, end: m.end, slot: m.slot };
        s.count++;
        s.buffered += len;
        s.len = len;
        if (m.end) {
          s.hasEnd = true;
        }
      }

      // hard cap 400 ms, and the backlog a TCP stall flushes at once (more
      // than 2 frames over the target once 10 ms pass without a frame): the
      // oldest frames go, down to the target, so a stall adds no lasting delay
      trim(s, now) {
        if (s.buffered > 400 * this.ms || (s.buffered > s.target + 2 * s.len && now - s.lastAt > 10 * this.ms)) {
          while (s.count > 0 && s.buffered > s.target) {
            var f = s.frames[s.next];
            if (f) {
              s.frames[s.next] = null;
              s.count--;
              s.buffered -= f.pcm.length;
              this.st.trimmed++;
            }
            s.next = (s.next + 1) & 255;
          }
        }
      }

      // the next frame to play, a concealment, or false (spurt over)
      advance(s) {
        var f = s.frames[s.next];
        if (f) {
          s.frames[s.next] = null;
          s.count--;
          s.buffered -= f.pcm.length;
          s.next = (s.next + 1) & 255;
          s.cur = f.pcm;
          s.last = f.pcm;
          s.pos = 0;
          s.miss = 0;
          s.endAfter = !!f.end;
          s.slot = f.slot; // a concealment keeps the slot of the frame before
          this.st.played++;
          return true;
        }
        if (!s.last && s.count > 0) {
          // the first frames never came (dropped as stale): start at the
          // oldest one buffered
          for (var skip = 1; skip < 64 && !s.frames[(s.next + skip) & 255]; skip++) {
            // counting
          }
          s.next = (s.next + skip) & 255;
          return this.advance(s);
        }
        if (s.endAfter || s.miss >= 3 || !s.last) {
          this.reset(s);
          return false;
        }
        // missing when due: 10 ms fade of the last frame's tail, then silence
        var n = s.last.length;
        var pcm = new Float32Array(n);
        if (s.miss === 0) {
          var fade = Math.min(480, n);
          for (var i = 0; i < fade; i++) {
            pcm[i] = s.last[n - fade + i] * (1 - i / fade);
          }
        }
        s.miss++;
        s.next = (s.next + 1) & 255;
        s.cur = pcm;
        s.pos = 0;
        this.st.conceal++;
        return true;
      }

      // the current frame of s from out[i] on, at most to n: where it
      // stopped. Mixed into out, the left channel (copied to the right once
      // the block is mixed); z: the speaker's place (a slot-3 frame), its
      // left gain into out and right - left into sd
      run(s, z, g, out, sd, i, n) {
        var cur = s.cur;
        var len = cur.length;
        var p = s.pos;
        var step = this.step;
        var a, b, v;
        if (!z) {
          if (step === 1) {
            var take = Math.min(n - i, len - p);
            for (var k = 0; k < take; k++) {
              out[i + k] += cur[p + k] * g;
            }
            s.pos = p + take;
            return i + take;
          }
          // 48 kHz frames into another context rate
          while (i < n && p < len) {
            a = Math.floor(p);
            b = a + 1 < len ? cur[a + 1] : cur[a];
            out[i++] += (cur[a] + (b - cur[a]) * (p - a)) * g;
            p += step;
          }
          s.pos = p;
          return i;
        }
        var cl = z.cl;
        var cr = z.cr;
        var rn = z.n;
        if (step === 1 && rn === 0) {
          // where it settled (nearly always): two gains, as tight as a centred voice
          var cnt = Math.min(n - i, len - p);
          var gl = g * cl;
          var gd = g * (cr - cl);
          for (var q = 0; q < cnt; q++) {
            v = cur[p + q];
            out[i + q] += v * gl;
            sd[i + q] += v * gd;
          }
          s.pos = p + cnt;
          return i + cnt;
        }
        while (i < n && p < len) {
          if (step === 1) {
            v = cur[p++] * g;
          } else {
            a = Math.floor(p);
            b = a + 1 < len ? cur[a + 1] : cur[a];
            v = (cur[a] + (b - cur[a]) * (p - a)) * g;
            p += step;
          }
          if (rn > 0) {
            // a new place: one linear step per sample, 50 ms in all
            if (--rn === 0) {
              cl = z.tl;
              cr = z.tr;
            } else {
              cl += z.dl;
              cr += z.dr;
            }
          }
          out[i] += v * cl;
          sd[i++] += v * (cr - cl);
        }
        z.cl = cl;
        z.cr = cr;
        z.n = rn;
        s.pos = p;
        return i;
      }

      // soft limiter: transparent up to 0.9, never past 1
      limit(out, n) {
        for (var i = 0; i < n; i++) {
          var x = out[i];
          if (x > 0.9) {
            out[i] = 0.9 + 0.1 * Math.tanh((x - 0.9) * 10);
          } else if (x < -0.9) {
            out[i] = -0.9 - 0.1 * Math.tanh((-x - 0.9) * 10);
          }
        }
      }

      process(inputs, outputs) {
        var o = outputs[0];
        var out = o && o[0];
        if (!out) {
          return true;
        }
        var outR = o[1]; // stereo (outputChannelCount [2]); absent: a mono node
        var n = out.length;
        var now = this.clock();
        var self = this;
        var wide = false; // a voice with a place in this block: left and right differ
        if (this.sp.size > 0) {
          this.sp.forEach(function (s, sid) {
            if (s.state !== 0) {
              self.trim(s, now);
            }
            if (s.state === 1) {
              var wait = 120 * self.ms + (s.target - 80 * self.ms);
              if (s.buffered >= s.target || now - s.firstAt >= wait || s.hasEnd) {
                s.state = 2;
              } else {
                return;
              }
            }
            if (s.state !== 2) {
              return;
            }
            var ug = (self.users.has(sid) ? self.users.get(sid) : 1) * self.master;
            if (self.deaf && sid !== 65536) { // TEST_SID: the local test still plays
              ug = 0;
            }
            var i = 0;
            while (i < n) {
              if (!s.cur || s.pos >= s.cur.length) {
                if (!self.advance(s)) {
                  break;
                }
              }
              // the gains of the frame being played (its own slot)
              var sv = self.slots[s.slot];
              var z = s.slot === 3 ? self.spatial.get(sid) : undefined;
              if (z && !wide) {
                wide = true;
                if (!self.sd || self.sd.length !== n) {
                  self.sd = new Float32Array(n);
                } else {
                  self.sd.fill(0);
                }
              }
              i = self.run(s, z, ug * (sv === undefined ? 1 : sv), out, self.sd, i, n);
            }
          });
          if (wide) {
            var sd = this.sd;
            if (outR) {
              for (var w = 0; w < n; w++) {
                outR[w] = out[w] + sd[w];
              }
              this.limit(outR, n);
            } else {
              for (var m = 0; m < n; m++) {
                out[m] += 0.5 * sd[m]; // the middle of left and right
              }
            }
            this.limit(out, n);
          } else {
            this.limit(out, n);
            if (outR) {
              outR.set(out); // centred: the mono mix on both sides
            }
          }
        }
        if (this.probe) {
          var r = outR || out;
          var sum = 0;
          var sumR = 0;
          for (var j = 0; j < n; j++) {
            sum += out[j] * out[j];
            sumR += r[j] * r[j];
            var ax = out[j] < 0 ? -out[j] : out[j];
            var ay = r[j] < 0 ? -r[j] : r[j];
            if (ax > this.peak) {
              this.peak = ax;
            }
            if (ay > this.peak) {
              this.peak = ay;
            }
          }
          this.psum += sum;
          this.psumR += sumR;
          this.pn += n;
          if (dbOf((sum + sumR) / 2, n) > ONSET_DB) {
            if (this.quiet >= 0.3 * sampleRate) {
              this.port.postMessage({ t: 'o' });
            }
            this.quiet = 0;
          } else {
            this.quiet += n;
          }
        }
        // speakers silent for 10 s are forgotten (the decoder goes too)
        if (++this.tick >= 375) {
          this.tick = 0;
          this.sp.forEach(function (s, sid) {
            if (s.state === 0 && now - s.lastAt > 10 * IN) {
              self.sp.delete(sid);
            }
          });
        }
        return true;
      }
    }

    registerProcessor('mv-capture', MvCapture);
    registerProcessor('mv-mixer', MvMixer);
  }

  // ---------------------------------------------------------------------------
  // state

  var st = {
    // settings, kept across connections (the game sends them once)
    tx: -1, // the slot the capture sends on: the key's, or the mouse button's while held
    keyTx: -1, // the slot of the push-to-talk key ('tx' command)
    vad: false,
    vadDb: -45,
    preset: 0,
    inGain: 1,
    outVol: 1,
    users: new Map(),
    spatial: new Map(), // sid -> { g, p }: the place of its slot-3 (near) frames
    slotGain: [1, 1, 1, 1],
    deaf: false,
    smute: false,
    meter: false,
    test: false,
    probe: false,
    indev: '',
    outdev: '',
    pttBtn: 0,
    pttSlot: -1,
    // connection
    conn: null,
    connAt: -1e9, // the last time there was a connection (or a try)
    sid: 0,
    rooms: [null, null, null, null], // per slot: party, guild, public, near
    seq: 0,
    maxOpus: MAX_OPUS, // the relay's limit (welcome lim.pl)
    // audio
    ctx: null,
    audioP: null,
    anyRate: false,
    mixer: null,
    cap: null,
    micSrc: null,
    micStream: null,
    micP: null,
    micToken: 0,
    micState: 'off',
    micDeniedAt: -1e9,
    micUsedAt: 0,
    micPerm: 'unknown', // the Permissions API's answer: granted|denied|prompt|unknown
    micUnresolved: false, // opened while the saved device had no id yet (no labels)
    gate: false,
    enc: null,
    presetBad: [false, false, false], // presets this browser cannot encode
    encCoolUntil: 0,
    encFailing: false,
    testSeq: 0,
    decoders: new Map(),
    decCool: new Map(),
    speakers: new Map(),
    spkTimer: 0,
    house: 0,
    mouseTx: false,
    mouseAt: 0,
    activeAt: 0,
    sleeping: false, // suspended by us when idle
    wantRun: false, // a wake is due: a press resumes the context
    needGesture: false, // resume() outside a press did not start audio here: no idle sleep
    devs: { ins: [], outs: [], idIn: {}, idOut: {}, key: '' },
    devKeySent: '',
    devWatch: false,
    resuming: null,
    mix: null,
    mixWait: [],
    lat: { cap: [], out: [] },
    n: { upF: 0, upB: 0, upDrop: 0, upBig: 0, upNoRoom: 0, micMove: 0, stalls: 0, resyncs: 0, encOut: 0, encErr: 0, encNew: 0, inMsg: 0, inB: 0, inF: 0, inOpus: 0, inEnd: 0, deafDrop: 0, decOut: 0, decErr: 0, decNew: 0, ctlIn: 0, ctlOut: 0, sockets: 0, jsErr: 0 }
  };

  function now() {
    return performance.now();
  }

  function clamp(x, lo, hi, d) {
    x = Number(x);
    if (!isFinite(x)) {
      return d;
    }
    return Math.min(hi, Math.max(lo, x));
  }

  // The game page shows its crash screen on any uncaught error
  // (window.onerror in shell.html): nothing of the voice may ever reach it.
  // Every callback the browser calls goes through safe(); errors are counted
  // and the last one shows in the stats.
  var lastError = '';

  function note(e) {
    st.n.jsErr++;
    lastError = String((e && e.message) || e).slice(0, 200);
  }

  function safe(fn) {
    return function () {
      try {
        return fn.apply(this, arguments);
      } catch (e) {
        note(e);
      }
    };
  }

  // ---------------------------------------------------------------------------
  // support (computed once at load; C++ reads it with MythosVoice.support())

  var support = null; // null pending, then true or false
  var useVoiceHints = false;

  function encConfig(p) {
    var pr = PRESETS[p] || PRESETS[0];
    var opus = { format: 'opus', frameDuration: pr.frame * 1000000 / RATE, complexity: 5, usedtx: false, useinbandfec: false };
    if (useVoiceHints) {
      opus.signal = 'voice';
      opus.application = 'voip';
    }
    return { codec: 'opus', sampleRate: RATE, numberOfChannels: 1, bitrate: pr.bitrate, bitrateMode: 'variable', opus: opus };
  }

  var DEC_CONFIG = { codec: 'opus', sampleRate: RATE, numberOfChannels: 1 };

  function detect() {
    try {
      detectNow();
    } catch (e) {
      support = false;
    }
  }

  function detectNow() {
    var w = window;
    if (!w.AudioEncoder || !w.AudioDecoder || !w.AudioData || !w.EncodedAudioChunk || !w.AudioWorkletNode ||
        !w.AudioContext || !w.WebSocket || !w.isSecureContext) {
      support = false;
      return;
    }
    var hinted = encConfig(0);
    hinted.opus.signal = 'voice';
    hinted.opus.application = 'voip';
    var maybe = function (cfg) {
      return AudioEncoder.isConfigSupported(cfg).catch(function () {
        return { supported: false };
      });
    };
    Promise.all([
      AudioEncoder.isConfigSupported(encConfig(0)),
      AudioDecoder.isConfigSupported(DEC_CONFIG),
      maybe(hinted),
      maybe(encConfig(1)),
      maybe(encConfig(2))
    ]).then(safe(function (r) {
      var c = r[2].config && r[2].config.opus;
      useVoiceHints = !!(r[2].supported && c && c.signal === 'voice' && c.application === 'voip');
      support = !!(r[0].supported && r[1].supported);
      // eco (60 ms frames) or high refused: those presets encode as normal
      st.presetBad[1] = st.presetBad[1] || !r[3].supported;
      st.presetBad[2] = st.presetBad[2] || !r[4].supported;
      pushCapture();
      emitCaps();
    }), function () {
      support = false;
    });
    watchPermission();
  }

  function emitCaps() {
    emit({ t: 'caps', s: JSON.stringify({ ok: support, hints: useVoiceHints, sink: !!(window.AudioContext && AudioContext.prototype.setSinkId),
      presets: [1, st.presetBad[1] ? 0 : 1, st.presetBad[2] ? 0 : 1] }) });
  }

  // Whether the page may already use the microphone without asking: the
  // level meter opens it only then (opening the settings window must not
  // bring up the browser's prompt, which can drop fullscreen).
  function watchPermission() {
    var perms = navigator.permissions;
    if (!perms || typeof perms.query !== 'function') {
      return; // 'unknown' until a getUserMedia works
    }
    try {
      perms.query({ name: 'microphone' }).then(safe(function (status) {
        if (st.micPerm !== 'granted' || status.state !== 'prompt') {
          st.micPerm = status.state;
        }
        status.onchange = safe(function () {
          st.micPerm = status.state;
          if (status.state === 'granted' && (st.micState === 'denied' || st.micState === 'nodevice')) {
            // allowed in the browser's site settings: the next need opens it
            st.micState = 'off';
            st.micDeniedAt = -1e9;
          }
          if (status.state === 'granted') {
            refreshDevices(); // the labels (and saved devices) show now
          }
        });
      }), function () {});
    } catch (e) {
      // a browser that does not know 'microphone' as a permission name
    }
  }

  // the meter may open the microphone: no prompt can come of it
  function micQuiet() {
    return !!st.micStream || st.micPerm === 'granted';
  }

  // ---------------------------------------------------------------------------
  // events to the game

  var sink = null;
  var attached = false;
  var queue = [];
  var flushing = false;
  var stalled = false; // the game's inbox was full: no flush before the retry
  var resyncing = false; // compact() ending a connection: its last events are dropped

  function emit(ev) {
    if (resyncing) {
      return;
    }
    queue.push(ev);
    if (queue.length >= MAX_QUEUED_EVENTS) {
      compact();
    }
    schedule();
  }

  function schedule() {
    if (!flushing && !stalled && queue.length && (sink || attached)) {
      flushing = true;
      Promise.resolve().then(flushSafe);
    }
  }

  function flush() {
    flushing = false;
    if (!queue.length) {
      return;
    }
    var batch = queue;
    queue = [];
    if (sink) {
      try {
        sink(batch);
      } catch (e) {
        // the page's handler is not our concern
      }
      return;
    }
    if (!toModule(JSON.stringify(batch))) {
      // the game is not polling (its inbox is full): the events wait here
      queue = batch.concat(queue);
      stalled = true;
      st.n.stalls++;
      setTimeout(safe(function () {
        stalled = false;
        schedule();
      }), STALL_RETRY_MS);
    }
  }

  function flushSafe() {
    try {
      flush();
    } catch (e) {
      note(e);
    }
  }

  // MAX_QUEUED_EVENTS events the game has not taken (no command yet, or a
  // game thread that stopped polling: a hidden tab stops its frames). What
  // only matters live goes first: levels, stats, all but the last 'talk'. If
  // that is not enough, the connection's own events (control messages in
  // order, speaking edges) cannot all be kept: the connection ends here, and
  // the game gets one 'closed' (1006) and joins again from a fresh welcome.
  // 'state', 'mic', 'devices' and 'caps' are never lost: the newest of each
  // stays.
  function compact() {
    var lastTalk = -1;
    for (var i = queue.length - 1; i >= 0 && lastTalk < 0; i--) {
      if (queue[i].t === 'talk') {
        lastTalk = i;
      }
    }
    queue = queue.filter(function (e, k) {
      return e.t !== 'level' && e.t !== 'stats' && (e.t !== 'talk' || k === lastTalk);
    });
    if (queue.length < MAX_QUEUED_EVENTS / 2) {
      return;
    }
    var c = st.conn;
    if (c) {
      resyncing = true;
      try {
        closeSocket();
        endConnection();
      } finally {
        resyncing = false;
      }
      st.n.resyncs++;
    }
    var seen = {};
    var out = [];
    for (var j = queue.length - 1; j >= 0; j--) {
      var t = queue[j].t;
      if ((t === 'caps' || t === 'devices' || t === 'mic' || t === 'talk' || (t === 'state' && !c)) && !seen[t]) {
        seen[t] = true;
        out.unshift(queue[j]);
      }
    }
    if (c) {
      out.push({ t: 'state', s: 'closed', a: 1006, g: c.gen });
    }
    queue = out;
  }

  // into the C++ inbox: a malloc'd copy (a roster can be tens of KB, too
  // much for ccall's stack copy), or ccall for small batches on old builds.
  // false: the inbox is full (otc_voice_event returned 0), the batch is
  // kept for later; anything else (taken, too big, no runtime) is done with.
  function toModule(text) {
    var M = window.Module;
    if (!M || typeof M._otc_voice_event !== 'function') {
      return true;
    }
    try {
      if (M._malloc && M._free && M.stringToUTF8 && M.lengthBytesUTF8) {
        var size = M.lengthBytesUTF8(text) + 1;
        var ptr = M._malloc(size);
        if (!ptr) {
          return true;
        }
        M.stringToUTF8(text, ptr, size);
        var r;
        try {
          r = M._otc_voice_event(ptr);
        } finally {
          M._free(ptr);
        }
        return r !== 0;
      } else if (M.ccall && text.length < 16000) {
        return M.ccall('otc_voice_event', 'number', ['string'], [text]) !== 0;
      }
    } catch (e) {
      // the runtime is gone (page leaving)
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // audio context and worklets

  var workletUrl = null;

  function getWorkletUrl() {
    if (!workletUrl) {
      workletUrl = URL.createObjectURL(new Blob([window.MythosVoice.workletSource()], { type: 'application/javascript' }));
    }
    return workletUrl;
  }

  function ensureAudio() {
    if (st.audioP) {
      return st.audioP;
    }
    var ctx;
    var opts = { latencyHint: 'interactive' };
    if (!st.anyRate) {
      opts.sampleRate = RATE;
    }
    try {
      ctx = new AudioContext(opts);
    } catch (e) {
      try {
        ctx = new AudioContext({ latencyHint: 'interactive' });
      } catch (e2) {
        return Promise.reject(e2);
      }
    }
    st.ctx = ctx;
    st.sleeping = false;
    st.wantRun = false;
    st.resuming = null;
    st.activeAt = now();
    ctx.onstatechange = safe(function () {
      if (st.ctx !== ctx) {
        return;
      }
      if (ctx.state === 'running') {
        st.wantRun = false;
        st.resuming = null; // an older pending resume() no longer matters
        disarmResume();
      } else if (ctx.state !== 'closed' && !st.sleeping) {
        // stopped by the browser or the system (Safari: 'interrupted'), not by us
        st.wantRun = true;
        armResume();
      }
    });
    var p = ctx.audioWorklet.addModule(getWorkletUrl()).then(function () {
      if (st.ctx !== ctx) {
        throw new Error('stale context');
      }
      // stereo: a proximity voice has a side; every other voice is centred
      var mixer = new AudioWorkletNode(ctx, 'mv-mixer', { numberOfInputs: 0, numberOfOutputs: 1, outputChannelCount: [2] });
      mixer.onprocessorerror = safe(function () {
        note('mixer stopped');
      });
      mixer.port.onmessage = safe(onMixerMsg);
      mixer.connect(ctx.destination);
      st.mixer = mixer;
      pushMixer();
      st.users.forEach(function (x, sid) {
        mixer.port.postMessage({ t: 'u', sid: sid, x: x });
      });
      st.spatial.forEach(function (v, sid) {
        mixer.port.postMessage({ t: 'sp', sid: sid, g: v.g, p: v.p });
      });
      applySink();
      wake();
      watchDevices();
      startHouse();
      return ctx;
    });
    st.audioP = p;
    p.catch(function () {
      if (st.ctx === ctx) {
        closeAudio();
      }
    });
    return p;
  }

  function closeAudio() {
    releaseMic();
    retireEncoder();
    closeDecoders();
    var ctx = st.ctx;
    st.ctx = null;
    st.audioP = null;
    st.mixer = null;
    st.sleeping = false;
    st.wantRun = false;
    st.resuming = null;
    disarmResume();
    if (ctx) {
      ctx.onstatechange = null;
      ctx.close().catch(function () {});
    }
  }

  // Starting and waking the context. The "Jogar" click gives the page sticky
  // activation, and Chrome then lets resume() start audio from anywhere: an
  // incoming frame wakes the context from its idle sleep. Where the context
  // still does not run (made before any press, or a browser that starts
  // audio only inside a press), the next press or key resumes it. That
  // resume() is always issued, even with an earlier one still pending: Blink
  // keeps a resume() made without activation pending until audio starts, so
  // waiting for it would wait forever. A key alone does not wake a context
  // we put to sleep: only a due wake (wantRun) does.
  var gestureArmed = false;

  var onGesture = safe(function () {
    var ctx = st.ctx;
    if (!ctx || ctx.state === 'running' || ctx.state === 'closed') {
      disarmResume();
      return;
    }
    if (st.wantRun) {
      ctx.resume().catch(function () {});
    }
  });

  function armResume() {
    if (!gestureArmed) {
      gestureArmed = true;
      window.addEventListener('pointerdown', onGesture, true);
      window.addEventListener('keydown', onGesture, true);
    }
  }

  function disarmResume() {
    if (gestureArmed) {
      gestureArmed = false;
      window.removeEventListener('pointerdown', onGesture, true);
      window.removeEventListener('keydown', onGesture, true);
    }
  }

  function wake() {
    st.activeAt = now();
    var ctx = st.ctx;
    if (!ctx || ctx.state === 'running' || ctx.state === 'closed') {
      return;
    }
    st.sleeping = false;
    st.wantRun = true;
    armResume();
    if (st.resuming) {
      return;
    }
    var r = ctx.resume();
    st.resuming = r;
    var done = function () {
      if (st.resuming === r) {
        st.resuming = null;
      }
    };
    r.then(done, done);
    setTimeout(safe(function () {
      if (st.ctx === ctx && st.wantRun && ctx.state !== 'running' && ctx.state !== 'closed') {
        // a resume() outside a press did not start audio: asleep, the context
        // could not be woken by an incoming voice, so from now on it stays
        // awake (Chrome after the "Jogar" click never gets here)
        st.needGesture = true;
      }
    }), WAKE_CHECK_MS);
  }

  function pushMixer() {
    if (st.mixer) {
      st.mixer.port.postMessage({ t: 'cfg', slots: st.slotGain.slice(), master: st.outVol, deaf: st.deaf, probe: st.probe });
    }
  }

  function applySink() {
    var ctx = st.ctx;
    if (!ctx || typeof ctx.setSinkId !== 'function') {
      return;
    }
    var id = (st.outdev && st.devs.idOut[st.outdev]) || '';
    if ((ctx.sinkId || '') !== id) {
      ctx.setSinkId(id).catch(function () {});
    }
  }

  function onMixerMsg(e) {
    var m = e.data;
    if (m.t === 's') {
      st.mix = m;
      var waiting = st.mixWait;
      st.mixWait = [];
      waiting.forEach(function (fn) {
        fn();
      });
    } else if (m.t === 'o') {
      var ctx = st.ctx;
      var outMs = ctx ? ((ctx.outputLatency || 0) + (ctx.baseLatency || 0)) * 1000 : 0;
      pushLat(st.lat.out, performance.timeOrigin + now() + outMs);
    }
  }

  function pushLat(list, t) {
    list.push(t);
    if (list.length > 20) {
      list.shift();
    }
  }

  // ---------------------------------------------------------------------------
  // microphone

  // The microphone is asked for only by a press (push-to-talk, the mic test)
  // or by voice activation, which the player chose; the level meter of the
  // settings window uses it only when that brings up no prompt.
  function needMic() {
    return st.tx >= 0 || st.mouseTx || st.test || (st.meter && micQuiet()) || st.probe || vadArmed();
  }

  // voice activation never talks in near (slot 3) by itself: with only near
  // joined it would send to strangers on screen without a key press
  function hasVadRoom() {
    return !!(st.rooms[0] || st.rooms[1] || st.rooms[2]);
  }

  // voice activation listens only while it could send: connected, in a
  // room, not self-muted (in no room every spurt would be dropped)
  function vadArmed() {
    return st.vad && !st.smute && !!st.conn && hasVadRoom();
  }

  // something is captured or played on purpose: the context must run (the
  // capture worklet does nothing in a suspended one)
  function busy() {
    return st.gate || st.test || st.meter || st.probe || st.tx >= 0 || st.mouseTx || (vadArmed() && !!(st.micStream || st.micP));
  }

  function ensureMic() {
    st.micUsedAt = now();
    wake(); // the context may be asleep (idle): the capture needs it running
    if (st.micStream || st.micP) {
      return;
    }
    if (now() - st.micDeniedAt < MIC_RETRY_MS) {
      return;
    }
    var md = navigator.mediaDevices;
    if (!md || !md.getUserMedia) {
      st.micDeniedAt = now();
      setMic('nodevice');
      return;
    }
    var token = ++st.micToken;
    st.micState = 'opening';
    st.micP = ensureAudio().then(function (ctx) {
      var asked = { unresolved: false };
      return openMic(asked).then(function (stream) {
        if (token !== st.micToken || st.ctx !== ctx) {
          stopStream(stream);
          return;
        }
        attachMic(ctx, stream, token, asked.unresolved);
      });
    }).catch(function (e) {
      if (token !== st.micToken) {
        return;
      }
      st.micP = null;
      var name = (e && e.name) || '';
      var denied = name === 'NotAllowedError' || name === 'SecurityError' || name === 'PermissionDeniedError';
      st.micDeniedAt = now();
      if (denied) {
        st.micPerm = 'denied';
      }
      setMic(denied ? 'denied' : 'nodevice');
    });
  }

  // asked.unresolved: the saved device has no id yet (the browser lists no
  // labels before the permission), so the default device opens; once the
  // list has labels, refreshDevices moves the microphone to it
  function openMic(asked) {
    var id = (st.indev && st.devs.idIn[st.indev]) || '';
    asked.unresolved = !!st.indev && !id;
    var c = { channelCount: 1, echoCancellation: true, noiseSuppression: true, autoGainControl: true };
    if (id) {
      c.deviceId = { exact: id };
    }
    return navigator.mediaDevices.getUserMedia({ audio: c, video: false }).catch(function (e) {
      if (id && e && (e.name === 'OverconstrainedError' || e.name === 'NotFoundError')) {
        delete c.deviceId; // that device is gone: the default one
        return navigator.mediaDevices.getUserMedia({ audio: c, video: false });
      }
      throw e;
    });
  }

  function attachMic(ctx, stream, token, unresolved) {
    var src;
    try {
      src = ctx.createMediaStreamSource(stream);
    } catch (e) {
      // Firefox: a microphone at another rate cannot join a 48 kHz context;
      // the context goes back to the default rate and the worklets resample
      stopStream(stream);
      if (!st.anyRate) {
        st.anyRate = true;
        st.micP = null;
        closeAudio();
        ensureMic();
        return;
      }
      throw e;
    }
    var cap = new AudioWorkletNode(ctx, 'mv-capture', { numberOfInputs: 1, numberOfOutputs: 0, channelCount: 1, channelCountMode: 'explicit', channelInterpretation: 'speakers' });
    cap.onprocessorerror = safe(function () {
      note('capture stopped');
    });
    cap.port.onmessage = safe(onCaptureMsg);
    src.connect(cap);
    st.cap = cap;
    st.micSrc = src;
    st.micStream = stream;
    st.micP = null;
    st.micPerm = 'granted';
    st.micUnresolved = !!unresolved;
    pushCapture();
    wake(); // the prompt may have taken longer than the idle sleep
    stream.getAudioTracks().forEach(function (track) {
      track.onended = safe(function () {
        if (st.micStream === stream && token === st.micToken) {
          releaseMic();
          setMic('nodevice'); // unplugged
        }
      });
    });
    setMic('ok');
    refreshDevices();
  }

  function setMic(s) {
    st.micState = s === 'ok' ? 'on' : s;
    emit({ t: 'mic', s: s });
  }

  function stopStream(stream) {
    if (stream) {
      stream.getTracks().forEach(function (t) {
        t.onended = null;
        t.stop();
      });
    }
  }

  function releaseMic() {
    st.micToken++;
    st.micP = null;
    st.micUnresolved = false;
    if (st.cap) {
      st.cap.port.postMessage({ t: 'stop' });
      st.cap.port.onmessage = null;
      st.cap = null;
    }
    if (st.micSrc) {
      try {
        st.micSrc.disconnect();
      } catch (e) {
        // already disconnected
      }
      st.micSrc = null;
    }
    stopStream(st.micStream);
    st.micStream = null;
    if (st.micState === 'on' || st.micState === 'opening') {
      st.micState = 'off';
    }
    if (st.gate) {
      st.gate = false;
      emit({ t: 'talk', a: -1 });
    }
  }

  function pushCapture(now) {
    if (st.cap) {
      var tx = st.deaf || st.smute ? -1 : st.tx;
      st.cap.port.postMessage({ t: 'cfg', tx: tx, vad: st.vad && !!st.conn && hasVadRoom(), vadDb: st.vadDb, gain: st.inGain, muted: st.smute || st.deaf, test: st.test, meter: st.meter, frame: PRESETS[usePreset()].frame, vadSlot: vadSlot(), probe: st.probe, now: !!now });
    }
  }

  // the player's preset, or normal where this browser cannot encode it
  function usePreset() {
    var p = PRESETS[st.preset] ? st.preset : 0;
    return st.presetBad[p] ? 0 : p;
  }

  // the preset for frames of n samples: the player's, else one this browser
  // encodes with that frame size (-1: none, the capture changes size)
  function presetFor(n) {
    var order = [usePreset(), 0, 2, 1];
    for (var i = 0; i < order.length; i++) {
      var p = order[i];
      if (!st.presetBad[p] && PRESETS[p].frame === n) {
        return p;
      }
    }
    return -1;
  }

  // voice activation talks in the party room, else the first room joined
  // (guild, public); never near, which needs its key
  function vadSlot() {
    for (var i = 0; i < 3; i++) {
      if (st.rooms[i]) {
        return i;
      }
    }
    return 0;
  }

  function onCaptureMsg(e) {
    var m = e.data;
    if (m.t === 'f') {
      st.micUsedAt = now();
      wake();
      encodeFrame(m);
    } else if (m.t === 'g') {
      st.gate = m.on === 1;
      emit({ t: 'talk', a: m.on === 1 ? m.slot : -1 });
    } else if (m.t === 'l') {
      if (st.meter) {
        emit({ t: 'level', a: Math.max(-100, Math.round(m.db)) });
      }
    } else if (m.t === 'o') {
      pushLat(st.lat.cap, performance.timeOrigin + now());
    }
  }

  // ---------------------------------------------------------------------------
  // encoding and sending

  function makeEncoder(frame, p) {
    var e = { enc: null, meta: [], frame: frame, preset: p, broken: false, failed: false, out: 0, idx: 0 };
    st.n.encNew++;
    try {
      e.enc = new AudioEncoder({
        output: safe(function (chunk) {
          onChunk(e, chunk);
        }),
        error: safe(function (err) {
          encFailed(e, err);
        })
      });
      e.enc.configure(encConfig(p));
    } catch (err) {
      encFailed(e, err);
    }
    return e;
  }

  // An encoder that failed. One that never gave a frame could not take its
  // settings: a preset other than normal is then dropped for this page (the
  // frames change size at once), and normal itself waits ENC_COOL_MS before
  // a new try, with one 'mic encoder' event until a frame comes out. One the
  // browser took back (QuotaExceededError: codecs reclaimed) or that failed
  // after working is only replaced.
  function encFailed(e, err) {
    if (e.failed) {
      return;
    }
    e.failed = true;
    e.broken = true;
    e.meta.length = 0;
    st.n.encErr++;
    var name = (err && err.name) || '';
    if (name === 'QuotaExceededError') {
      return;
    }
    if (e.out === 0 && e.preset !== 0) {
      if (!st.presetBad[e.preset]) {
        st.presetBad[e.preset] = true;
        pushCapture(true);
        emitCaps();
      }
      return;
    }
    st.encCoolUntil = now() + ENC_COOL_MS;
    if (e.out === 0 && !st.encFailing) {
      st.encFailing = true;
      emit({ t: 'mic', s: 'encoder' });
    }
  }

  function retireEncoder() {
    var e = st.enc;
    st.enc = null;
    if (e && e.enc) {
      // pending frames still come out; closed a moment later
      setTimeout(function () {
        try {
          e.enc.close();
        } catch (err) {
          // already closed
        }
      }, e.meta.length ? 500 : 0);
    }
  }

  function encodeFrame(m) {
    var net = m.net === 1 && canSend();
    if (net && !st.rooms[m.slot & 3]) {
      net = false; // not in a room on that slot: the relay would drop it
      st.n.upNoRoom++;
    }
    var test = st.test;
    if (!net && !test) {
      return;
    }
    var n = m.pcm.length;
    var e = st.enc;
    if (!e || e.broken || e.frame !== n || (m.first === 1 && e.preset !== usePreset())) {
      retireEncoder();
      var p = presetFor(n);
      if (p < 0 || now() < st.encCoolUntil) {
        st.n.upDrop++;
        return;
      }
      e = st.enc = makeEncoder(n, p);
    }
    if (e.broken || e.enc.encodeQueueSize > 8) {
      st.n.upDrop++;
      return;
    }
    var data;
    try {
      data = new AudioData({ format: 'f32', sampleRate: RATE, numberOfFrames: n, numberOfChannels: 1, timestamp: e.idx++ * n * 1000000 / RATE, data: m.pcm });
    } catch (err) {
      st.n.upDrop++;
      return;
    }
    e.meta.push({ net: net, end: m.end === 1, slot: m.slot & 3, vad: m.vad === 1, test: test });
    try {
      e.enc.encode(data);
    } catch (err) {
      encFailed(e, err);
    }
    data.close();
  }

  function canSend() {
    var c = st.conn;
    return !!(c && c.open && st.sid && !st.deaf && !st.smute);
  }

  function onChunk(e, chunk) {
    var m = e.meta.shift();
    if (!m) {
      return; // a chunk without a frame (the encoder's own padding)
    }
    e.out++;
    st.encFailing = false;
    st.n.encOut++;
    var n = chunk.byteLength;
    if (n < 1 || n > MAX_OPUS) {
      st.n.upBig++;
      return;
    }
    var c = st.conn;
    if (m.net && c && c.open) {
      if (n > st.maxOpus) {
        st.n.upBig++; // over the relay's limit: it would count it as abuse
      } else if (c.ws.bufferedAmount > SEND_BACKLOG) {
        st.n.upDrop++; // the socket is stuck: late audio is worthless
      } else {
        var b = new Uint8Array(3 + n);
        b[0] = 0x01;
        b[1] = (m.slot & 3) | (m.end ? 4 : 0) | (m.vad ? 8 : 0);
        b[2] = st.seq;
        st.seq = (st.seq + 1) & 255;
        chunk.copyTo(b.subarray(3));
        c.ws.send(b);
        st.n.upF++;
        st.n.upB += b.length;
      }
    }
    if (m.test) {
      var d = new Uint8Array(n);
      chunk.copyTo(d);
      st.testSeq = (st.testSeq + 1) & 255;
      onFrame(2 | (m.end ? 4 : 0), TEST_SID, st.testSeq, d, now());
    }
  }

  // ---------------------------------------------------------------------------
  // receiving, decoding, speaking edges

  function onBinary(buf) {
    var b = new Uint8Array(buf);
    st.n.inMsg++;
    st.n.inB += b.length;
    var t = now();
    if (b[0] === 0x01) {
      if (b.length > 5 && b.length <= 5 + MAX_OPUS) {
        onFrame(b[1], b[2] | (b[3] << 8), b[4], b.subarray(5), t);
      }
    } else if (b[0] === 0x02 && b.length > 2) {
      var count = b[1];
      var p = 2;
      for (var i = 0; i < count && p < b.length; i++) {
        var len = b[p];
        if (len <= 4 || len > 4 + MAX_OPUS || p + 1 + len > b.length) {
          return;
        }
        var e = p + 1;
        onFrame(b[e], b[e + 1] | (b[e + 2] << 8), b[e + 3], b.subarray(e + 4, e + len), t);
        p = e + len;
      }
    }
  }

  function onFrame(flags, sid, seq, opus, t) {
    var end = (flags & 4) !== 0;
    if (sid !== TEST_SID) {
      st.n.inF++;
      st.n.inOpus += opus.length;
      if (end) {
        st.n.inEnd++;
      }
      speaking(sid, opus.length, end, t);
      if (st.deaf) {
        st.n.deafDrop++;
        return;
      }
    }
    if (!st.mixer) {
      return;
    }
    if (st.ctx && st.ctx.state !== 'running') {
      wake();
    }
    st.activeAt = t;
    var cool = st.decCool.get(sid);
    if (cool) {
      if (t < cool) {
        return;
      }
      st.decCool.delete(sid);
    }
    var d = decoder(sid, t);
    if (!d) {
      return;
    }
    if (d.dec.decodeQueueSize > 8 || d.meta.length > 16) {
      dropDecoder(sid, 'stuck');
      return;
    }
    d.meta.push({ seq: seq, end: end, slot: flags & 3 });
    try {
      d.dec.decode(new EncodedAudioChunk({ type: 'key', timestamp: d.ts, data: opus }));
      d.ts += 40000;
    } catch (err) {
      dropDecoder(sid, 'error');
    }
  }

  function decoder(sid, t) {
    var d = st.decoders.get(sid);
    if (d) {
      d.last = t;
      return d;
    }
    if (st.decoders.size >= MAX_DECODERS) {
      var oldest = -1;
      var at = Infinity;
      st.decoders.forEach(function (x, k) {
        if (x.last < at) {
          at = x.last;
          oldest = k;
        }
      });
      dropDecoder(oldest, null);
    }
    d = { sid: sid, dec: null, meta: [], last: t, ts: 0 };
    try {
      d.dec = new AudioDecoder({
        output: safe(function (data) {
          onDecoded(d, data);
        }),
        error: safe(function () {
          if (st.decoders.get(sid) === d) {
            dropDecoder(sid, 'error');
          }
        })
      });
      d.dec.configure(DEC_CONFIG);
    } catch (err) {
      st.n.decErr++;
      st.decCool.set(sid, t + 1000);
      return null;
    }
    st.n.decNew++;
    st.decoders.set(sid, d);
    return d;
  }

  function dropDecoder(sid, why) {
    var d = st.decoders.get(sid);
    if (!d) {
      return;
    }
    st.decoders.delete(sid);
    try {
      d.dec.close();
    } catch (err) {
      // closed by its error already
    }
    if (why) {
      st.n.decErr++;
      st.decCool.set(sid, now() + 1000); // no create-fail loop on bad packets
    }
    if (st.mixer) {
      st.mixer.port.postMessage({ t: 'drop', sid: sid });
    }
  }

  function closeDecoders() {
    st.decoders.forEach(function (d) {
      try {
        d.dec.close();
      } catch (err) {
        // already closed
      }
    });
    st.decoders.clear();
    st.decCool.clear();
  }

  function onDecoded(d, data) {
    var m = d.meta.shift();
    if (!m || !st.mixer || st.decoders.get(d.sid) !== d) {
      data.close();
      return;
    }
    var n = data.numberOfFrames;
    var pcm = new Float32Array(n);
    try {
      data.copyTo(pcm, { planeIndex: 0, format: 'f32-planar' });
    } catch (err) {
      try {
        data.copyTo(pcm, { planeIndex: 0 });
      } catch (err2) {
        data.close();
        return;
      }
    }
    data.close();
    st.n.decOut++;
    st.mixer.port.postMessage({ t: 'p', sid: d.sid, slot: m.slot, seq: m.seq, end: m.end, pcm: pcm }, [pcm.buffer]);
  }

  // on: the first frame over 10 B; off: END or 300 ms without frames
  function speaking(sid, len, end, t) {
    var s = st.speakers.get(sid);
    if (!s) {
      s = { on: false, last: t };
      st.speakers.set(sid, s);
    }
    s.last = t;
    if (end) {
      if (s.on) {
        s.on = false;
        emitSpk(sid, 0);
      }
      return;
    }
    if (!s.on && len > SPEECH_MIN) {
      s.on = true;
      emitSpk(sid, 1);
      if (!st.spkTimer) {
        st.spkTimer = setInterval(safe(spkTick), 100);
      }
    }
  }

  function emitSpk(sid, on) {
    emit({ t: 'spk', a: sid, b: on, g: st.conn ? st.conn.gen : 0 });
  }

  function spkTick() {
    var t = now();
    var any = false;
    st.speakers.forEach(function (s, sid) {
      if (s.on) {
        if (t - s.last > SPK_GAP_MS) {
          s.on = false;
          emitSpk(sid, 0);
        } else {
          any = true;
        }
      }
    });
    if (!any) {
      clearInterval(st.spkTimer);
      st.spkTimer = 0;
    }
  }

  function speakersOff() {
    st.speakers.forEach(function (s, sid) {
      if (s.on) {
        emitSpk(sid, 0);
      }
    });
    st.speakers.clear();
    if (st.spkTimer) {
      clearInterval(st.spkTimer);
      st.spkTimer = 0;
    }
  }

  // ---------------------------------------------------------------------------
  // the socket

  function connect(c) {
    closeSocket();
    endConnection();
    var gen = c.g | 0;
    var conn = { ws: null, gen: gen, open: false };
    st.conn = conn;
    st.seq = 0;
    st.n.sockets++;
    emit({ t: 'state', s: 'connecting', a: 0, g: gen });
    ensureAudio().catch(function () {});
    refreshDevices();
    var ws;
    try {
      ws = new WebSocket(String(c.url || ''), 'mythos-voice.1');
    } catch (err) {
      st.conn = null;
      emit({ t: 'state', s: 'closed', a: 1006, g: gen });
      return;
    }
    conn.ws = ws;
    ws.binaryType = 'arraybuffer';
    var tok = String(c.tok || '');
    ws.onopen = safe(function () {
      if (st.conn !== conn) {
        return;
      }
      conn.open = true;
      ws.send(JSON.stringify({ t: 'hello', v: 1, tok: tok, cl: String(c.cl || 'web'), b: String(c.b || '').slice(0, 40), a: 1 }));
      tok = '';
      emit({ t: 'state', s: 'open', a: 0, g: gen });
    });
    ws.onmessage = safe(function (ev) {
      if (st.conn !== conn) {
        return;
      }
      if (typeof ev.data === 'string') {
        st.n.ctlIn++;
        trackRooms(ev.data);
        emit({ t: 'ctl', s: ev.data, g: gen });
      } else {
        onBinary(ev.data);
      }
    });
    ws.onerror = function () {
      // the close event follows with the code
    };
    ws.onclose = safe(function (ev) {
      if (st.conn !== conn) {
        return;
      }
      st.conn = null;
      st.connAt = now();
      emit({ t: 'state', s: 'closed', a: ev.code || 1006, g: gen });
      endConnection();
    });
  }

  // a socket we close ourselves reports nothing (a new connect may follow)
  function closeSocket() {
    var c = st.conn;
    st.conn = null;
    if (c) {
      st.connAt = now();
    }
    if (c && c.ws) {
      var ws = c.ws;
      ws.onopen = ws.onmessage = ws.onerror = ws.onclose = null;
      try {
        ws.close(1000);
      } catch (err) {
        // never opened
      }
    }
  }

  function endConnection() {
    st.sid = 0;
    st.rooms = [null, null, null, null];
    st.maxOpus = MAX_OPUS;
    st.users.clear(); // sids belong to one relay session; the game sends them again
    st.spatial.clear();
    st.tx = -1;
    st.keyTx = -1;
    st.mouseTx = false;
    speakersOff();
    closeDecoders();
    if (st.mixer) {
      st.mixer.port.postMessage({ t: 'reset' });
    }
    pushCapture();
  }

  // end: the game is closing (terminate), the meter goes too; otherwise the
  // settings window may still be open, and its meter goes on (the game sends
  // 'meter' only when the window opens)
  function disconnect(end) {
    closeSocket();
    endConnection();
    st.test = false;
    if (end) {
      st.meter = false;
    }
    closeAudio();
    stopHouse();
    if (st.meter && micQuiet()) {
      ensureMic();
    }
  }

  // the rooms we are in, from the relay's own messages (voice activation and
  // the mouse button need the slot); every relay message starts {"t":"
  function trackRooms(text) {
    if (text.length > 65536 || text.indexOf('{"t":"') !== 0) {
      return;
    }
    var t = text.slice(6, 14);
    if (t.indexOf('welcome"') !== 0 && t.indexOf('roster"') !== 0 && t.indexOf('left"') !== 0 && t.indexOf('moved"') !== 0) {
      return;
    }
    var m;
    try {
      m = JSON.parse(text);
    } catch (err) {
      return;
    }
    if (m.t === 'welcome') {
      st.sid = m.sid | 0;
      st.rooms = [null, null, null, null];
      var pl = m.lim && Number(m.lim.pl);
      st.maxOpus = pl >= 1 ? Math.min(MAX_OPUS, Math.floor(pl)) : MAX_OPUS;
    } else if (m.t === 'roster' || m.t === 'moved') {
      var slot = m.slot | 0;
      if (slot >= 0 && slot <= 3) {
        st.rooms[slot] = m.t === 'roster' ? m.room : m.to;
      }
    } else if (m.t === 'left') {
      forgetRoom(m.room);
    }
    pushCapture();
    // voice activation opens the microphone once there is a room to talk in
    if (vadArmed() && !st.micStream && !st.micP && st.micState !== 'denied' && st.micState !== 'nodevice') {
      ensureMic();
    }
  }

  function forgetRoom(id) {
    for (var i = 0; i < 4; i++) {
      if (st.rooms[i] === id) {
        st.rooms[i] = null;
      }
    }
  }

  function sendCtl(text) {
    var c = st.conn;
    if (!c || !c.open || typeof text !== 'string' || !text.length) {
      return;
    }
    if (text.indexOf('"leave"') >= 0) {
      try {
        var m = JSON.parse(text);
        if (m.t === 'leave') {
          forgetRoom(m.room);
          pushCapture();
        }
      } catch (err) {
        // the relay answers bad_msg
      }
    }
    c.ws.send(text);
    st.n.ctlOut++;
  }

  // ---------------------------------------------------------------------------
  // push-to-talk extras: focus loss, the side mouse buttons

  function forceRelease() {
    if (st.tx >= 0 || st.keyTx >= 0 || st.mouseTx) {
      st.tx = -1;
      st.keyTx = -1;
      st.mouseTx = false;
      pushCapture();
      emit({ t: 'talk', a: -1 });
    }
  }

  window.addEventListener('blur', safe(forceRelease));
  document.addEventListener('visibilitychange', safe(function () {
    if (document.hidden) {
      forceRelease();
    }
  }));

  var mouseOn = false;

  var onMouseDown = safe(function (e) {
    if (e.button !== st.pttBtn) {
      return;
    }
    e.preventDefault();
    e.stopPropagation();
    var slot = st.pttSlot;
    if (slot < 0 || !st.rooms[slot] || st.deaf || st.smute || !canSend()) {
      return;
    }
    st.mouseTx = true;
    st.mouseAt = now();
    st.tx = slot;
    ensureMic(); // wakes the context too
    pushCapture();
  });

  // the mouse button let go (or held too long): a push-to-talk key still
  // held goes on talking
  function mouseRelease() {
    st.mouseTx = false;
    st.tx = st.keyTx;
    pushCapture();
  }

  var onMouseUp = safe(function (e) {
    if (e.button !== st.pttBtn) {
      return;
    }
    e.preventDefault();
    e.stopPropagation();
    if (st.mouseTx) {
      mouseRelease();
    }
  });

  // the browser goes Back/Forward on these buttons unless stopped
  var onAux = safe(function (e) {
    if (e.button === st.pttBtn) {
      e.preventDefault();
    }
  });

  function setPttMouse(btn, slot) {
    btn = btn | 0;
    slot = slot | 0;
    var on = (btn === 3 || btn === 4) && slot >= 0 && slot <= 3;
    st.pttBtn = on ? btn : 0;
    st.pttSlot = on ? slot : -1;
    if (on !== mouseOn) {
      mouseOn = on;
      var f = on ? document.addEventListener : document.removeEventListener;
      f.call(document, 'mousedown', onMouseDown, true);
      f.call(document, 'mouseup', onMouseUp, true);
      f.call(document, 'auxclick', onAux, true);
    }
    if (!on && st.mouseTx) {
      mouseRelease();
    }
  }

  // ---------------------------------------------------------------------------
  // devices

  function watchDevices() {
    var md = navigator.mediaDevices;
    if (st.devWatch || !md || !md.addEventListener) {
      return;
    }
    st.devWatch = true;
    md.addEventListener('devicechange', safe(onDeviceChange));
  }

  // a device came or went: a microphone that was missing may be back
  function onDeviceChange() {
    refreshDevices();
    if (st.micState === 'nodevice' && !st.micStream && !st.micP) {
      st.micState = 'off';
      st.micDeniedAt = -1e9;
      if (needMic()) {
        ensureMic();
      }
    }
  }

  function trackDevice(stream) {
    var tr = stream && stream.getAudioTracks()[0];
    try {
      return (tr && tr.getSettings && tr.getSettings().deviceId) || '';
    } catch (e) {
      return '';
    }
  }

  function refreshDevices() {
    var md = navigator.mediaDevices;
    if (!md || !md.enumerateDevices) {
      return;
    }
    md.enumerateDevices().then(safe(function (list) {
      var ins = [];
      var outs = [];
      var idIn = {};
      var idOut = {};
      var canSink = !!(window.AudioContext && AudioContext.prototype.setSinkId);
      list.forEach(function (d) {
        // labels show only once the page may use the microphone; the
        // browser's own "default"/"communications" entries are the '' choice
        if (!d.label || d.deviceId === 'default' || d.deviceId === 'communications') {
          return;
        }
        var names = d.kind === 'audioinput' ? ins : (d.kind === 'audiooutput' && canSink ? outs : null);
        if (!names || names.length >= 32) {
          return;
        }
        var ids = names === ins ? idIn : idOut;
        var name = d.label.slice(0, 80);
        for (var k = 2; ids[name] !== undefined; k++) {
          name = d.label.slice(0, 74) + ' (' + k + ')';
        }
        ids[name] = d.deviceId;
        names.push(name);
      });
      var key = JSON.stringify([ins, outs]);
      st.devs = { ins: ins, outs: outs, idIn: idIn, idOut: idOut, key: key };
      if (key !== st.devKeySent) {
        st.devKeySent = key;
        emit({ t: 'devices', i: ins, o: outs });
      }
      // the microphone opened on the default device because the saved one
      // had no id yet: now that the list has labels, it moves there, once
      if (st.micUnresolved && st.micStream && ins.length) {
        st.micUnresolved = false;
        var want = idIn[st.indev];
        if (want && trackDevice(st.micStream) !== want) {
          st.n.micMove++;
          releaseMic();
          ensureMic();
        }
      }
      applySink(); // the saved output device, once it has an id
    })).catch(function () {});
  }

  // ---------------------------------------------------------------------------
  // housekeeping, once a second while there is audio

  function startHouse() {
    if (!st.house) {
      st.house = setInterval(safe(house), 1000);
    }
  }

  function stopHouse() {
    if (st.house) {
      clearInterval(st.house);
      st.house = 0;
    }
  }

  // how long an unused microphone stays open: 5 min while connected (the
  // next press starts at once), 30 s once not connected for 30 s (voice
  // off, or given up); a reconnect's backoff keeps it, its tries come less
  // than 30 s apart
  function micIdleLimit(t) {
    return st.conn || t - st.connAt < MIC_IDLE_OFF_MS ? MIC_IDLE_MS : MIC_IDLE_OFF_MS;
  }

  function house() {
    var t = now();
    if (st.conn) {
      st.connAt = t;
    }
    st.decoders.forEach(function (d, sid) {
      if (t - d.last > DECODER_IDLE_MS) {
        dropDecoder(sid, null);
      }
    });
    st.speakers.forEach(function (s, sid) {
      if (!s.on && t - s.last > DECODER_IDLE_MS) {
        st.speakers.delete(sid);
      }
    });
    if (st.mouseTx && t - st.mouseAt > MOUSE_TX_MAX_MS) {
      mouseRelease();
    }
    if (needMic()) {
      st.micUsedAt = t;
      // a refusal waits for the player (or the site settings); a missing or
      // busy microphone is tried again now and then
      if (!st.micStream && !st.micP && st.micState !== 'denied' && (st.micState !== 'nodevice' || t - st.micDeniedAt > NODEV_RETRY_MS)) {
        ensureMic();
      }
    } else if ((st.micStream || st.micP) && (t - st.micUsedAt > micIdleLimit(t) || (st.vad && st.smute))) {
      releaseMic();
    }
    var ctx = st.ctx;
    if (!ctx) {
      stopHouse();
      return;
    }
    var b = busy();
    if (b) {
      st.activeAt = t;
      if (ctx.state !== 'running' && ctx.state !== 'closed') {
        wake(); // whatever path forgot to: the capture needs it running
      }
    }
    if (!st.conn && !st.micStream && !st.micP && !b && t - st.activeAt > AUDIO_IDLE_CLOSE_MS) {
      closeAudio();
      stopHouse();
      return;
    }
    // nothing heard or said for a while: the audio thread sleeps until the
    // next frame or the next use of the microphone (every path that needs
    // the capture goes through ensureMic(), which wakes it)
    if (ctx.state === 'running' && !b && !st.needGesture && t - st.activeAt > IDLE_SUSPEND_MS) {
      st.sleeping = true;
      st.wantRun = false;
      st.resuming = null;
      armResume(); // should the next wake not start it, the press after it will
      ctx.suspend().catch(function () {});
    }
  }

  // ---------------------------------------------------------------------------
  // commands from the game

  function cmd(x) {
    try {
      runCmd(x);
    } catch (e) {
      note(e);
    }
  }

  function runCmd(x) {
    attached = true;
    schedule();
    var c = x;
    if (typeof x === 'string') {
      try {
        c = JSON.parse(x);
      } catch (err) {
        return;
      }
    }
    if (!c || typeof c.op !== 'string') {
      return;
    }
    switch (c.op) {
      case 'connect':
        connect(c);
        break;
      case 'disconnect':
        disconnect(!!c.end);
        break;
      case 'ctl':
        sendCtl(c.json);
        break;
      case 'tx':
        var k = clamp(c.slot, -1, 3, -1) | 0;
        if (k >= 0 && (st.deaf || st.smute)) {
          k = -1;
        }
        st.keyTx = k;
        // the side mouse button, still held, keeps its slot
        st.tx = st.mouseTx ? st.pttSlot : k;
        if (st.tx >= 0) {
          ensureMic(); // wakes the context too
        }
        pushCapture();
        break;
      // The game sends every setting again each time one changes (a slider
      // step, a checkbox): a setting that did not change does nothing.
      case 'mode':
        if (st.vad !== !!c.vad) {
          st.vad = !!c.vad;
          if (vadArmed()) {
            ensureMic();
          }
          pushCapture();
        }
        break;
      case 'vad':
        st.vadDb = clamp(c.db, -90, 0, -45);
        pushCapture();
        break;
      case 'preset':
        st.preset = clamp(c.p, 0, 2, 0) | 0;
        pushCapture();
        break;
      case 'mic':
        if (c.on) {
          ensureMic();
        } else {
          releaseMic();
        }
        break;
      case 'indev':
        var indev = String(c.id || '');
        if (indev !== st.indev) {
          st.indev = indev;
          if (st.micStream || st.micP) {
            releaseMic(); // another device: the microphone opens again on it
            ensureMic();
          }
        }
        break;
      case 'outdev':
        st.outdev = String(c.id || '');
        applySink();
        break;
      case 'ingain':
        st.inGain = clamp(c.x, 0, 2, 1);
        pushCapture();
        break;
      case 'outvol':
        st.outVol = clamp(c.x, 0, 2, 1);
        pushMixer();
        break;
      case 'uvol':
        var sid = c.sid | 0;
        var ux = clamp(c.x, 0, 2, 1);
        if (ux === 1) {
          st.users.delete(sid);
        } else {
          st.users.set(sid, ux);
        }
        if (st.mixer) {
          st.mixer.port.postMessage({ t: 'u', sid: sid, x: ux });
        }
        break;
      case 'svol':
        var slot = c.slot | 0;
        if (slot >= 0 && slot <= 3) {
          st.slotGain[slot] = clamp(c.x, 0, 2, 1);
          pushMixer();
        }
        break;
      // a near speaker's place, for its frames on slot 3 only (game_voice
      // calls it a few times a second while that speaker talks, on a change)
      case 'spatial':
        var psid = c.sid | 0;
        var pg = clamp(c.g, 0, 1, 1);
        var pp = clamp(c.p, -1, 1, 0);
        var was = st.spatial.get(psid);
        if (!was || was.g !== pg || was.p !== pp) {
          st.spatial.set(psid, { g: pg, p: pp });
          if (st.mixer) {
            st.mixer.port.postMessage({ t: 'sp', sid: psid, g: pg, p: pp });
          }
        }
        break;
      case 'deaf':
        if (st.deaf === !!c.on) {
          break;
        }
        st.deaf = !!c.on;
        if (st.deaf) {
          st.tx = -1;
          st.keyTx = -1;
          st.mouseTx = false;
        }
        pushMixer();
        pushCapture();
        break;
      case 'smute':
        if (st.smute === !!c.on) {
          break;
        }
        st.smute = !!c.on;
        if (st.smute) {
          st.tx = -1;
          st.keyTx = -1;
          st.mouseTx = false;
          if (st.vad && !needMic()) {
            releaseMic(); // the browser's microphone indicator tells the truth
          }
        } else if (vadArmed()) {
          ensureMic();
        }
        pushCapture();
        break;
      case 'meter':
        if (st.meter !== !!c.on) {
          st.meter = !!c.on;
          pushCapture();
        }
        if (st.meter && micQuiet()) {
          ensureMic(); // else it shows the level once a press opens the microphone
        }
        break;
      case 'pttMouse':
        setPttMouse(c.btn, c.slot);
        break;
      case 'test':
        st.test = !!c.on;
        if (st.test) {
          ensureMic();
        } else if (st.mixer) {
          st.mixer.port.postMessage({ t: 'drop', sid: TEST_SID });
        }
        pushCapture();
        break;
      case 'probe':
        st.probe = !!c.on;
        if (st.probe) {
          ensureAudio().catch(function () {});
        }
        pushMixer();
        pushCapture();
        break;
      case 'stats':
        statsEvent();
        break;
    }
  }

  function snapshot() {
    var n = st.n;
    var ctx = st.ctx;
    var mem = performance.memory;
    return {
      v: VERSION,
      sup: support,
      state: st.conn ? (st.conn.open ? 'open' : 'connecting') : 'idle',
      sid: st.sid,
      rooms: st.rooms.slice(),
      slots: st.slotGain.slice(),
      spatial: spatialList(),
      ctx: ctx ? ctx.state : 'none',
      wake: { want: st.wantRun, needPress: st.needGesture, armed: gestureArmed },
      rate: ctx ? ctx.sampleRate : 0,
      sinkId: ctx && typeof ctx.sinkId === 'string' ? ctx.sinkId : '',
      lat: ctx ? Math.round(((ctx.outputLatency || 0) + (ctx.baseLatency || 0)) * 1000) : 0,
      mic: st.micState,
      micMoves: n.micMove,
      perm: st.micPerm,
      queue: { n: queue.length, stalls: n.stalls, resyncs: n.resyncs, stalled: stalled },
      tx: st.tx,
      keyTx: st.keyTx,
      mouseTx: st.mouseTx,
      vad: st.vad,
      gate: st.gate,
      deaf: st.deaf,
      smute: st.smute,
      preset: st.preset,
      up: { f: n.upF, b: n.upB, drop: n.upDrop, big: n.upBig, noRoom: n.upNoRoom, max: st.maxOpus, enc: n.encOut, encErr: n.encErr, encNew: n.encNew, presets: [1, st.presetBad[1] ? 0 : 1, st.presetBad[2] ? 0 : 1] },
      down: { m: n.inMsg, b: n.inB, f: n.inF, opus: n.inOpus, end: n.inEnd, deaf: n.deafDrop, dec: n.decOut, decErr: n.decErr, decNew: n.decNew },
      ctl: { i: n.ctlIn, o: n.ctlOut },
      sockets: n.sockets,
      decoders: st.decoders.size,
      speaking: Array.from(st.speakers.keys()).filter(function (sid) {
        return st.speakers.get(sid).on;
      }),
      mix: st.mix,
      heap: mem ? mem.usedJSHeapSize : 0,
      errors: n.jsErr,
      lastError: lastError,
      probe: { cap: st.lat.cap.slice(), out: st.lat.out.slice() }
    };
  }

  // the places the game gave: { sid: [gain, pan] }
  function spatialList() {
    var o = {};
    st.spatial.forEach(function (v, sid) {
      o[sid] = [v.g, v.p];
    });
    return o;
  }

  // asks the mixer for its counters, then emits (or answers fn)
  function freshStats(fn) {
    if (!st.mixer) {
      fn(snapshot());
      return;
    }
    var done = false;
    var finish = safe(function () {
      if (!done) {
        done = true;
        fn(snapshot());
      }
    });
    st.mixWait.push(finish);
    st.mixer.port.postMessage({ t: 's' });
    setTimeout(finish, 300);
  }

  function statsEvent() {
    freshStats(function (s) {
      emit({ t: 'stats', s: JSON.stringify(s) });
    });
  }

  detect();

  window.MythosVoice = {
    version: VERSION,
    // 1 supported, 0 not, 2 still checking (C++ asks again later)
    support: function () {
      return support === true ? 1 : (support === false ? 0 : 2);
    },
    cmd: cmd,
    setSink: function (fn) {
      sink = typeof fn === 'function' ? fn : null;
      schedule();
    },
    stats: snapshot,
    // the AudioWorklet module's source (test/worklet.mjs runs it in Node)
    workletSource: function () {
      return '(' + workletModule.toString() + ')();';
    },
    freshStats: function () {
      return new Promise(function (resolve) {
        freshStats(resolve);
      });
    }
  };
})();
