// Unit tests of the two AudioWorklet processors of mythos-voice.js, run in
// Node with a stub audio thread (no browser):
//
//   node worklet.mjs
//
// mv-mixer: the jitter policy of protocol I (start at 80 ms or 120 ms,
// reorder by u8 seq with wrap, concealment of a missing frame then silence
// after 3, late frames dropped, the 400 ms cap trimmed to the target, reset
// at END, J and the target), gains, deafen and the limiter.
// mv-capture: push-to-talk frames and END, voice activation with hysteresis,
// hangover and pre-roll, the preset frame size between spurts, the meter.
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const here = dirname(fileURLToPath(import.meta.url));
// MV_ENGINE: another copy of the engine (lint.mjs --minify: the minified one)
const engine = readFileSync(process.env.MV_ENGINE || join(here, '..', 'mythos-voice.js'), 'utf8');

// the engine's IIFE in a stub page, only to read the worklet source
const page = { addEventListener() {}, removeEventListener() {} };
const pageCtx = vm.createContext({ window: page, document: { addEventListener() {}, hidden: false }, performance: { now: () => 0, timeOrigin: 0 }, navigator: {}, Promise, JSON, Math, Map, Uint8Array, Float32Array, setTimeout, clearTimeout, setInterval, clearInterval });
page.window = page;
vm.runInContext(engine, pageCtx);
const source = page.MythosVoice.workletSource();

let failed = 0;
let passed = 0;
function check(name, ok, detail = '') {
  if (ok) passed++;
  else failed++;
  if (!ok || process.argv.includes('-v')) console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  ' + detail : ''}`);
}

// a fresh audio thread: processors registered by the module, a clock
function thread(rate = 48000) {
  const processors = {};
  const g = {
    sampleRate: rate,
    currentFrame: 0,
    registerProcessor: (name, cls) => {
      processors[name] = cls;
    },
    Math, Map, Float32Array, Array,
  };
  g.AudioWorkletProcessor = class {
    constructor() {
      const self = this;
      this.port = {
        posted: [],
        postMessage(m) {
          self.port.posted.push(m);
        },
        onmessage: null,
      };
    }
  };
  vm.runInContext(source, vm.createContext(g));
  return { g, processors };
}

// --- mixer -------------------------------------------------------------------

const F = 1920; // 40 ms
const BLOCK = 128;

function mixerRig() {
  const t = thread();
  const m = new t.processors['mv-mixer']();
  const send = (msg) => m.port.onmessage({ data: msg });
  const played = []; // per 128-sample block: the value heard (frames carry their seq as a constant)
  const step = (blocks = 1) => {
    for (let i = 0; i < blocks; i++) {
      const out = new Float32Array(BLOCK);
      m.process([], [[out]]);
      played.push(out);
      t.g.currentFrame += BLOCK;
    }
  };
  const pcm = (seq) => new Float32Array(F).fill(0.01 + (seq % 256) / 1000);
  const frame = (seq, opts = {}) => send({ t: 'p', sid: opts.sid || 1, slot: opts.slot || 0, seq: seq & 255, end: !!opts.end, pcm: opts.pcm || pcm(seq) });
  const ms = (x) => step(Math.round((x * 48) / BLOCK));
  // the seq heard in each frame-long stretch of output since block `from`
  const heard = (from = 0) => {
    const seqs = [];
    for (let i = from; i < played.length; i++) {
      const b = played[i];
      const v = b[0];
      const s = v > 0.005 && b[127] === v ? Math.round((v - 0.01) * 1000) : null;
      if (seqs.length === 0 || seqs[seqs.length - 1].s !== s) seqs.push({ s, at: i, n: 1 });
      else seqs[seqs.length - 1].n++;
    }
    return seqs;
  };
  const stats = () => {
    send({ t: 's' });
    return m.port.posted.filter((x) => x.t === 's').pop();
  };
  return { t, m, send, step, ms, frame, played, heard, stats, pcm };
}

{
  // a steady stream: starts once 80 ms are buffered, every frame once, in order
  const r = mixerRig();
  r.frame(10);
  r.ms(40);
  check('mixer: silent with one frame buffered (under 80 ms, under 120 ms)', r.played.every((b) => b[0] === 0));
  r.frame(11);
  r.ms(40);
  const startBlock = r.played.findIndex((b) => b[0] > 0);
  check('mixer: playback starts when 80 ms are buffered', startBlock >= 15 && startBlock <= 16, `block ${startBlock}`);
  for (let s = 12; s < 20; s++) {
    r.frame(s, { end: s === 19 });
    r.ms(40);
  }
  r.ms(200);
  const h = r.heard().filter((x) => x.s !== null);
  const seqs = h.map((x) => x.s);
  check('mixer: every frame played once, in order', JSON.stringify(seqs) === JSON.stringify([10, 11, 12, 13, 14, 15, 16, 17, 18, 19]), seqs.join(','));
  check('mixer: 40 ms per frame', h.slice(0, -1).every((x) => x.n === 15), h.map((x) => x.n).join(','));
  const st = r.stats();
  check('mixer: no concealment, no late frame on a steady stream', st.conceal === 0 && st.late === 0 && st.played === 10, JSON.stringify({ c: st.conceal, l: st.late, p: st.played }));
}

{
  // a single frame and nothing else: starts by the 120 ms rule
  const r = mixerRig();
  r.frame(1);
  r.ms(200);
  const start = r.played.findIndex((b) => b[0] > 0);
  check('mixer: a lone frame plays 120 ms after it arrived', start >= 44 && start <= 46, `block ${start} (~${Math.round((start * BLOCK) / 48)} ms)`);
}

{
  // reordering and the u8 wrap
  const r = mixerRig();
  for (const s of [254, 0, 255, 1]) r.frame(s);
  r.frame(2, { end: true });
  r.ms(400);
  const seqs = r.heard().filter((x) => x.s !== null).map((x) => x.s);
  check('mixer: reordered frames across the 255->0 wrap play in seq order', JSON.stringify(seqs) === JSON.stringify([254, 255, 0, 1, 2]), seqs.join(','));
}

{
  // a missing frame: 10 ms fade then silence for its slot; the late copy is dropped
  const r = mixerRig();
  r.frame(1);
  r.frame(2);
  r.ms(40);
  r.frame(4); // 3 is missing
  r.ms(40);
  r.frame(5);
  r.ms(40);
  r.frame(3); // too late now
  r.frame(6, { end: true });
  r.ms(300);
  const h = r.heard().map((x) => `${x.s === null ? '-' : x.s}x${x.n}`);
  const st = r.stats();
  const seqs = r.heard().filter((x) => x.s !== null).map((x) => x.s);
  check('mixer: a missing frame is concealed once and the rest plays on', st.conceal === 1 && JSON.stringify(seqs) === '[1,2,4,5,6]', `${h.join(' ')}; conceal ${st.conceal}`);
  check('mixer: a frame arriving after its turn is dropped as late', st.late === 1 && !seqs.slice(seqs.indexOf(4)).includes(3), `late ${st.late}`);
  // the concealed stretch fades: the first block after frame 2 is quieter than 2, then silence
  const i2 = r.heard().find((x) => x.s === 2);
  const after = r.played[i2.at + i2.n];
  check('mixer: concealment is a fade to silence', after && Math.abs(after[0]) <= 0.012 + 1e-6 && Math.abs(after[127]) < Math.abs(after[0]) + 1e-9, `first ${after && after[0].toFixed(4)}, last ${after && after[127].toFixed(4)}`);
}

{
  // four missing in a row: three concealed, then silence and wait; the next is a new spurt
  const r = mixerRig();
  r.frame(1);
  r.frame(2);
  r.ms(400);
  const st1 = r.stats();
  r.frame(9);
  r.ms(300);
  const st2 = r.stats();
  const seqs = r.heard().filter((x) => x.s !== null).map((x) => x.s);
  check('mixer: at most 3 concealments, then the speaker waits', st1.conceal === 3, `conceal ${st1.conceal}`);
  check('mixer: after the wait the next frame starts a new spurt', st2.spurts === 2 && seqs.includes(9), `spurts ${st2.spurts}, heard ${seqs.join(',')}`);
}

{
  // a TCP stall flushes 600 ms at once: trimmed to the target (80 ms), oldest first
  const r = mixerRig();
  for (let s = 0; s < 3; s++) {
    r.frame(s);
    r.ms(40);
  }
  for (let s = 3; s < 18; s++) r.frame(s, { end: s === 17 }); // 15 frames in one go
  r.ms(800);
  const st = r.stats();
  const seqs = r.heard().filter((x) => x.s !== null).map((x) => x.s);
  check('mixer: over 400 ms buffered, the oldest are dropped down to the target', st.trimmed >= 10 && seqs[seqs.length - 1] === 17, `trimmed ${st.trimmed}, heard ${seqs.join(',')}`);
  const lastBlock = r.heard().filter((x) => x.s !== null).pop();
  const endMs = ((lastBlock.at + lastBlock.n) * BLOCK) / 48 - 120;
  check('mixer: no lasting delay after the stall (the last frame ends within 200 ms)', endMs < 200, `${Math.round(endMs)} ms after the burst`);
}

{
  // END: the spurt ends after its last frame; the next spurt starts fresh
  const r = mixerRig();
  r.frame(1);
  r.frame(2, { end: true });
  r.ms(200);
  const st = r.stats();
  r.frame(100);
  r.frame(101, { end: true });
  r.ms(200);
  const st2 = r.stats();
  const seqs = r.heard().filter((x) => x.s !== null).map((x) => x.s);
  check('mixer: END plays at once (no 80 ms wait) and resets', JSON.stringify(seqs) === '[1,2,100,101]' && st.conceal === 0 && st2.spurts === 2, `heard ${seqs.join(',')}, conceal ${st.conceal}, spurts ${st2.spurts}`);
  const start = r.played.findIndex((b) => b[0] > 0);
  check('mixer: a short spurt with END starts at once', start <= 1, `block ${start}`);
}

{
  // jitter: arrivals +-20 ms around 40 ms raise the target above 80 ms, at most 240
  const r = mixerRig();
  const jit = [0, 30, 0, 30, 0, 30, 0, 30, 0, 30, 0, 30, 0, 30, 0, 30, 0, 30, 0, 30];
  for (let s = 0; s < 40; s++) {
    r.frame(s);
    r.ms(40 + (s % 2 ? 20 : -20));
  }
  const st = r.stats();
  const tgt = st.targets[1];
  check('mixer: J grows with jitter and the target follows (80 < target <= 240 ms)', tgt > 80 && tgt <= 240, `target ${tgt} ms`);
  void jit;
}

{
  // gains, deafen, limiter
  const r = mixerRig();
  r.send({ t: 'u', sid: 1, x: 0.5 });
  r.send({ t: 'cfg', slots: [1, 1, 1], master: 1, deaf: false, probe: false });
  r.frame(50);
  r.frame(51);
  r.ms(80);
  const v = r.played.find((b) => b[0] > 0);
  check('mixer: per-speaker volume', v && Math.abs(v[0] - 0.5 * (0.01 + 50 / 1000)) < 1e-6, v && v[0].toFixed(4));
  const r2 = mixerRig();
  r2.send({ t: 'cfg', slots: [0.5, 1, 1], master: 2, deaf: false, probe: false });
  r2.frame(50);
  r2.frame(51);
  r2.ms(80);
  const v2 = r2.played.find((b) => b[0] > 0);
  check('mixer: slot and master volume multiply', v2 && Math.abs(v2[0] - 0.06) < 1e-6, v2 && v2[0].toFixed(4));
  const r3 = mixerRig();
  r3.send({ t: 'cfg', slots: [1, 1, 1], master: 1, deaf: true, probe: false });
  r3.frame(50);
  r3.frame(51);
  r3.frame(1, { sid: 65536 }); // TEST_SID
  r3.frame(2, { sid: 65536 });
  r3.ms(120);
  const fromOthers = r3.played.slice(0, 15).every((b) => Math.abs(b[0] - (0.01 + 1 / 1000)) < 1e-6 || b[0] === 0);
  check('mixer: deafened hears nothing but its own microphone test', fromOthers && r3.played.some((b) => b[0] > 0), '');
  // sid 65535 is a real relay sid (1..65535): deafen silences it like any other
  const r3b = mixerRig();
  r3b.send({ t: 'cfg', slots: [1, 1, 1], master: 1, deaf: true, probe: false });
  r3b.frame(1, { sid: 65535 });
  r3b.frame(2, { sid: 65535 });
  r3b.ms(120);
  check('mixer: deafened silences sid 65535 (a real speaker, not the test)', r3b.played.every((b) => b[0] === 0), '');
  const r4 = mixerRig();
  const loud = new Float32Array(F).fill(3);
  r4.frame(1, { pcm: loud });
  r4.frame(2, { pcm: loud });
  r4.frame(1, { sid: 2, pcm: loud });
  r4.frame(2, { sid: 2, pcm: loud });
  r4.ms(120);
  const peak = Math.max(...r4.played.map((b) => Math.max(...b)));
  check('mixer: the limiter keeps two loud voices within [-1, 1]', peak <= 1 && peak > 0.95, `peak ${peak}`);
}

{
  // 48 kHz frames into a 44.1 kHz context (the Firefox fallback)
  const t = thread(44100);
  const m = new t.processors['mv-mixer']();
  const send = (msg) => m.port.onmessage({ data: msg });
  send({ t: 'p', sid: 1, slot: 0, seq: 0, end: false, pcm: new Float32Array(F).fill(0.2) });
  send({ t: 'p', sid: 1, slot: 0, seq: 1, end: true, pcm: new Float32Array(F).fill(0.2) });
  let n = 0;
  for (let i = 0; i < 100; i++) {
    const out = new Float32Array(BLOCK);
    m.process([], [[out]]);
    t.g.currentFrame += BLOCK;
    n += out.filter((x) => Math.abs(x - 0.2) < 1e-6).length;
  }
  check('mixer: 80 ms of 48 kHz audio lasts 80 ms at 44.1 kHz', Math.abs(n - 3528) <= 2, `${n} samples (3528 expected)`);
}

// --- capture -----------------------------------------------------------------

function captureRig(rate = 48000) {
  const t = thread(rate);
  const c = new t.processors['mv-capture']();
  const cfg = (o) => c.port.onmessage({ data: { t: 'cfg', tx: -1, vad: false, vadDb: -45, gain: 1, muted: false, test: false, meter: false, frame: F, vadSlot: 0, probe: false, ...o } });
  // feeds `ms` of input at a constant level (amplitude a: a sine, RMS a/sqrt2)
  let phase = 0;
  const feed = (ms, a) => {
    const blocks = Math.round((ms * rate) / 1000 / BLOCK);
    for (let i = 0; i < blocks; i++) {
      const ch = new Float32Array(BLOCK);
      for (let k = 0; k < BLOCK; k++) ch[k] = a * Math.sin((2 * Math.PI * 440 * phase++) / rate);
      c.process([[ch]], []);
    }
  };
  const posted = () => c.port.posted;
  const frames = () => posted().filter((m) => m.t === 'f');
  return { t, c, cfg, feed, posted, frames };
}

{
  const r = captureRig();
  r.cfg({});
  r.feed(400, 0.3);
  check('capture: idle push-to-talk posts nothing', r.posted().length === 0);
  r.cfg({ tx: 0 });
  r.feed(400, 0.3);
  r.cfg({ tx: -1 });
  r.feed(400, 0.3);
  const f = r.frames();
  const gates = r.posted().filter((m) => m.t === 'g').map((m) => m.on);
  check('capture: push-to-talk 400 ms -> 10 or 11 frames, the last one END', (f.length === 10 || f.length === 11) && f.filter((x) => x.end).length === 1 && f[f.length - 1].end === 1, `${f.length} frames, END ${f.map((x) => x.end).join('')}`);
  check('capture: gate edges on then off', JSON.stringify(gates) === '[1,0]', JSON.stringify(gates));
  check('capture: push-to-talk frames are not VAD, slot 0, 1920 samples', f.every((x) => x.vad === 0 && x.slot === 0 && x.pcm.length === F && x.net === 1));
  check('capture: the first frame of a spurt is marked', f[0].first === 1 && f.slice(1).every((x) => x.first === 0));
}

{
  // voice activation: quiet, loud 300 ms, quiet; hysteresis -6 dB, hangover 300 ms, pre-roll 1 frame
  const r = captureRig();
  r.cfg({ vad: true, vadDb: -30, vadSlot: 1 });
  r.feed(400, 0.001); // -63 dB
  check('capture: voice activation stays shut below the threshold', r.frames().length === 0);
  r.feed(320, 0.1); // -23 dB: over
  r.feed(160, 0.035); // -32 dB: under the threshold but within 6 dB: stays open
  r.feed(800, 0.001); // quiet: hangover then END
  const f = r.frames();
  const ends = f.filter((x) => x.end).length;
  check('capture: VAD opens with one frame of pre-roll', f.length > 0 && f[0].first === 1 && f[0].vad === 1 && f[0].slot === 1, `${f.length} frames`);
  // open for 1 pre-roll + 8 loud + 4 hysteresis + ~8 hangover frames
  check('capture: hysteresis and ~300 ms hangover, then END', ends === 1 && f.length >= 19 && f.length <= 23, `${f.length} frames, ${ends} END`);
  r.feed(400, 0.001);
  check('capture: closed after END', r.frames().length === f.length);
}

{
  // self-mute while talking closes the gate with END; eco frames between spurts
  const r = captureRig();
  r.cfg({ tx: 0 });
  r.feed(200, 0.3);
  r.cfg({ tx: 0, muted: true });
  r.feed(200, 0.3);
  const f = r.frames();
  check('capture: self-mute ends the spurt', f.length >= 5 && f[f.length - 1].end === 1, `${f.length}`);
  r.cfg({ tx: -1, frame: 2880 });
  r.cfg({ tx: 0, frame: 2880 });
  r.feed(300, 0.3);
  const g = r.frames().slice(f.length);
  check('capture: the eco preset gives 60 ms frames from the next spurt', g.length >= 4 && g.every((x) => x.pcm.length === 2880), g.map((x) => x.pcm.length).join(','));
  // mid-spurt: a new size waits for the END, unless the encoder needs it now
  const n0 = r.frames().length;
  r.cfg({ tx: 0, frame: F });
  r.feed(200, 0.3);
  const h = r.frames().slice(n0);
  check('capture: a preset change while talking waits for the next spurt', h.length >= 3 && h.every((x) => x.pcm.length === 2880), h.map((x) => x.pcm.length).join(','));
  r.cfg({ tx: 0, frame: 2880 });
  r.feed(200, 0.3);
  const n1 = r.frames().length;
  r.cfg({ tx: 0, frame: F, now: true });
  r.feed(200, 0.3);
  const k = r.frames().slice(n1);
  check('capture: now: true changes the frame size at once, the spurt goes on', k.length >= 4 && k.every((x) => x.pcm.length === F && x.end === 0 && x.first === 0), k.map((x) => x.pcm.length + (x.end ? 'E' : '')).join(','));
}

{
  // meter: a level every 100 ms only while metering
  const r = captureRig();
  r.cfg({ meter: true });
  r.feed(1000, 0.1);
  const levels = r.posted().filter((m) => m.t === 'l');
  check('capture: the meter posts 10 levels a second, about -23 dBFS', levels.length === 10 && Math.abs(levels[0].db + 23) < 1, `${levels.length}, ${levels[0] && levels[0].db.toFixed(1)} dB`);
  check('capture: metering alone sends no frame', r.frames().length === 0);
}

{
  // a 44.1 kHz microphone context (Firefox fallback): resampled to 48 kHz frames
  const r = captureRig(44100);
  r.cfg({ tx: 0 });
  r.feed(1000, 0.3);
  const f = r.frames();
  check('capture: 1 s at 44.1 kHz gives 25 frames of 48 kHz audio', f.length >= 24 && f.length <= 25 && f.every((x) => x.pcm.length === F), `${f.length}`);
}

console.log(`${passed} passed, ${failed} failed`);
process.exitCode = failed ? 1 : 0;
