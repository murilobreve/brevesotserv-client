// Unit tests of the two AudioWorklet processors of mythos-voice.js, run in
// Node with a stub audio thread (no browser):
//
//   node worklet.mjs
//
// mv-mixer: the jitter policy of protocol I (start at 80 ms or 120 ms,
// reorder by u8 seq with wrap, concealment of a missing frame then silence
// after 3, late frames dropped, the 400 ms cap trimmed to the target, reset
// at END, J and the target), gains, deafen and the limiter; stereo out:
// centred voices (left = right), a near speaker's place on slot 3 only
// (constant-power pan, gain, 50 ms ramp, the slot of the frame being
// played, no allocation per block).
// mv-capture: push-to-talk frames and END, voice activation with hysteresis,
// hangover and pre-roll, the preset frame size between spurts, the meter,
// slot 3.
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

// a fresh audio thread: processors registered by the module, a clock;
// counter: counts every Float32Array the processors make
function thread(rate = 48000, counter = null) {
  const processors = {};
  const F32 = counter
    ? class extends Float32Array {
      constructor(...a) {
        super(...a);
        counter.n++;
      }
    }
    : Float32Array;
  const g = {
    sampleRate: rate,
    currentFrame: 0,
    registerProcessor: (name, cls) => {
      processors[name] = cls;
    },
    Math, Map, Float32Array: F32, Array,
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

function mixerRig(rate = 48000, counter = null) {
  const t = thread(rate, counter);
  const m = new t.processors['mv-mixer']();
  const send = (msg) => m.port.onmessage({ data: msg });
  const played = []; // per 128-sample block: the value heard (frames carry their seq as a constant); left
  const playedR = []; // the right channel
  const step = (blocks = 1) => {
    for (let i = 0; i < blocks; i++) {
      const out = new Float32Array(BLOCK);
      const outR = new Float32Array(BLOCK);
      m.process([], [[out, outR]]);
      played.push(out);
      playedR.push(outR);
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
  // every sample since block `from`, one channel
  const samples = (blocks, from = 0) => {
    const outS = new Float32Array((blocks.length - from) * BLOCK);
    for (let i = from; i < blocks.length; i++) outS.set(blocks[i], (i - from) * BLOCK);
    return outS;
  };
  return { t, m, send, step, ms, frame, played, playedR, heard, stats, pcm, samples };
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
  check('mixer: stereo out, a voice with no place is centred (right = left, sample for sample)', r.played.every((b, i) => b.every((x, k) => x === r.playedR[i][k])) && r.playedR.some((b) => b[0] > 0));
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

// --- the near room (slot 3): a speaker's place in the stereo field ------------

const V = 0.2;
const R2 = Math.SQRT2 * V; // one side at pan -1 or 1: constant power, the centre is left = right = V
const flat = (x = V) => new Float32Array(F).fill(x);
const near = (r, seq, opts = {}) => r.frame(seq, { slot: 3, pcm: flat(opts.v), ...opts });
const close = (a, b, eps = 1e-5) => Math.abs(a - b) <= eps;
// the [left, right] of every block with sound, from block `from`
const loud = (r, from = 0) => {
  const outB = [];
  for (let i = from; i < r.played.length; i++) {
    const l = r.played[i];
    const rr = r.playedR[i];
    if (Math.abs(l[0]) > 1e-4 || Math.abs(rr[0]) > 1e-4) outB.push([l[0], rr[0], l[127], rr[127]]);
  }
  return outB;
};
const steady = (blocks, l, rr, eps = 1e-5) => blocks.length > 0 && blocks.every((b) => close(b[0], l, eps) && close(b[1], rr, eps) && close(b[2], l, eps) && close(b[3], rr, eps));
const fmt = (blocks) => (blocks.length ? `${blocks.length} blocks, first L ${blocks[0][0].toFixed(4)} R ${blocks[0][1].toFixed(4)}` : 'silent');

{
  // slot 3 with no place yet: centred, exactly as the other slots
  const r = mixerRig();
  near(r, 0);
  near(r, 1, { end: true });
  r.ms(200);
  const b = loud(r);
  check('near: a slot-3 voice with no place plays centred, as slot 0', steady(b, V, V) && b.length === 30, fmt(b));
}

{
  // pan -1, +1, 0 with gain 0.5, 0.5: set before the spurt (the voice starts there)
  const cases = [
    [1, -1, R2, 0, 'pan -1: all on the left, +3 dB on that side (constant power)'],
    [1, 1, 0, R2, 'pan +1: all on the right'],
    [0.5, 0, V * 0.5, V * 0.5, 'pan 0 gain 0.5: centred, half the amplitude'],
    [1, 0.5, R2 * Math.cos(1.5 * Math.PI / 4), R2 * Math.sin(1.5 * Math.PI / 4), 'pan 0.5: left^2 + right^2 is the centre\'s'],
  ];
  for (const [g, p, l, rr, name] of cases) {
    const r = mixerRig();
    r.send({ t: 'sp', sid: 1, g, p });
    near(r, 0);
    near(r, 1, { end: true });
    r.ms(200);
    const b = loud(r, 0);
    check(`near: ${name}`, steady(b, l, rr) && close(b[0][0] ** 2 + b[0][1] ** 2, 2 * (g * V) ** 2), `${fmt(b)}, expected L ${l.toFixed(4)} R ${rr.toFixed(4)}`);
  }
}

{
  // effective gain = master x slot volume[3] x user volume x spatial gain
  const r = mixerRig();
  r.send({ t: 'cfg', slots: [1, 1, 1, 0.5], master: 2, deaf: false, probe: false });
  r.send({ t: 'u', sid: 1, x: 0.5 });
  r.send({ t: 'sp', sid: 1, g: 0.8, p: 0 });
  near(r, 0);
  near(r, 1, { end: true });
  r.ms(200);
  const b = loud(r);
  check('near: master x slot 3 x user x spatial gain multiply', steady(b, V * 2 * 0.5 * 0.5 * 0.8, V * 2 * 0.5 * 0.5 * 0.8), fmt(b));
  // slot 3's volume only applies to slot 3
  const r2 = mixerRig();
  r2.send({ t: 'cfg', slots: [1, 1, 1, 0.5], master: 1, deaf: false, probe: false });
  r2.frame(0, { pcm: flat() });
  r2.frame(1, { pcm: flat(), end: true });
  r2.ms(200);
  check('near: slot 3\'s volume leaves slot 0 alone', steady(loud(r2), V, V), fmt(loud(r2)));
}

{
  // a place applies to slot 3 only: the same speaker on slots 0, 1, 2 plays centred
  let ok = true;
  const det = [];
  for (const slot of [0, 1, 2]) {
    const r = mixerRig();
    r.send({ t: 'sp', sid: 1, g: 0.3, p: -1 });
    r.frame(0, { slot, pcm: flat() });
    r.frame(1, { slot, pcm: flat(), end: true });
    r.ms(200);
    const b = loud(r);
    ok = ok && steady(b, V, V);
    det.push(`slot ${slot}: ${fmt(b)}`);
  }
  check('near: a place changes nothing on slots 0, 1, 2', ok, det.join('; '));
}

{
  // frames carry their slot: two on slot 3 then two on slot 0, all in before
  // the first plays. The side follows the frame being played, not the last arrival
  const r = mixerRig();
  r.send({ t: 'sp', sid: 1, g: 1, p: -1 });
  near(r, 0);
  near(r, 1);
  r.frame(2, { slot: 0, pcm: flat() });
  r.frame(3, { slot: 0, pcm: flat(), end: true });
  r.ms(300);
  const b = loud(r);
  const left = b.filter((x) => close(x[0], R2) && close(x[1], 0)).length;
  const mid = b.filter((x) => close(x[0], V) && close(x[1], V)).length;
  const order = b.findIndex((x) => close(x[1], V)) === left;
  check('near: slot 3 then slot 0 in one spurt: the first two frames on the left, the next two centred', left === 30 && mid === 30 && order, `left ${left} blocks, centred ${mid}, in order ${order}`);
  const r2 = mixerRig();
  r2.send({ t: 'sp', sid: 1, g: 1, p: 1 });
  r2.frame(0, { slot: 2, pcm: flat() });
  near(r2, 1);
  near(r2, 2, { end: true });
  r2.ms(300);
  const b2 = loud(r2);
  const mid2 = b2.filter((x) => close(x[0], V) && close(x[1], V)).length;
  const right2 = b2.filter((x) => close(x[0], 0) && close(x[1], R2)).length;
  check('near: slot 2 then slot 3: centred, then on the right', mid2 === 15 && right2 === 30 && b2.findIndex((x) => close(x[1], R2)) === 15, `centred ${mid2}, right ${right2}`);
}

{
  // a new place while the voice plays: a 50 ms linear ramp, no jump
  const r = mixerRig();
  r.send({ t: 'sp', sid: 1, g: 1, p: -1 });
  for (let s = 0; s < 4; s++) {
    near(r, s);
    r.ms(40);
  }
  const from = r.played.length;
  r.send({ t: 'sp', sid: 1, g: 1, p: 1 });
  for (let s = 4; s < 8; s++) {
    near(r, s, { end: s === 7 });
    r.ms(40);
  }
  const L = r.samples(r.played, from);
  const Rr = r.samples(r.playedR, from);
  let maxStep = 0;
  for (let i = 1; i < L.length; i++) maxStep = Math.max(maxStep, Math.abs(L[i] - L[i - 1]), Math.abs(Rr[i] - Rr[i - 1]));
  const firstMove = L.findIndex((x) => x < R2 - 1e-6);
  const settled = L.findIndex((x) => x < 1e-6);
  const powerOk = L.slice(0, 2400).every((x, i) => x * x + Rr[i] * Rr[i] <= 2 * V * V * 1.0001);
  check('near: a place changed while talking moves there in 50 ms (2400 samples), one small step per sample', firstMove === 0 && Math.abs(settled - 2400) <= 2 && close(Rr[2500], R2) && maxStep < 2 * R2 / 2400 + 1e-6 && powerOk,
    `moving from sample ${firstMove}, settled at ${settled}, largest step ${maxStep.toExponential(2)} (${(2 * R2 / 2400).toExponential(2)} per sample), never louder than the centre ${powerOk}`);
  // a place given while the speaker is silent: the next spurt starts there
  r.ms(400);
  r.send({ t: 'sp', sid: 1, g: 1, p: -1 });
  const from2 = r.played.length;
  near(r, 100);
  near(r, 101, { end: true });
  r.ms(200);
  const b = loud(r, from2);
  check('near: a place given between spurts applies from the first sample of the next', steady(b, R2, 0), fmt(b));
}

{
  // deafened: silent too; the limiter holds on the right channel
  const r = mixerRig();
  r.send({ t: 'cfg', slots: [1, 1, 1, 1], master: 1, deaf: true, probe: false });
  r.send({ t: 'sp', sid: 1, g: 1, p: 1 });
  near(r, 0);
  near(r, 1, { end: true });
  r.ms(200);
  check('near: deafened hears no near voice either', r.played.every((b) => b.every((x) => x === 0)) && r.playedR.every((b) => b.every((x) => x === 0)));
  const r2 = mixerRig();
  for (const sid of [1, 2]) {
    r2.send({ t: 'sp', sid, g: 1, p: 1 });
    r2.frame(0, { sid, slot: 3, pcm: flat(3) });
    r2.frame(1, { sid, slot: 3, pcm: flat(3), end: true });
  }
  r2.ms(200);
  const peakR = Math.max(...r2.playedR.map((b) => Math.max(...b)));
  const peakL = Math.max(...r2.played.map((b) => Math.max(...b.map(Math.abs))));
  check('near: the limiter keeps two loud voices on the right within [-1, 1]', peakR <= 1 && peakR > 0.95 && peakL < 1e-6, `right ${peakR}, left ${peakL}`);
}

{
  // 'reset' (a new connection: sids are another session's) forgets the places;
  // 'drop' (the decoder went) does not
  const r = mixerRig();
  r.send({ t: 'sp', sid: 1, g: 1, p: -1 });
  r.send({ t: 'drop', sid: 1 });
  near(r, 0);
  near(r, 1, { end: true });
  r.ms(200);
  const kept = steady(loud(r), R2, 0);
  r.send({ t: 'reset' });
  const from = r.played.length;
  near(r, 50);
  near(r, 51, { end: true });
  r.ms(200);
  check('near: a place survives the decoder going, not a new connection', kept && steady(loud(r, from), V, V) && r.stats().spatial === 0, fmt(loud(r, from)));
}

{
  // 48 kHz frames into a 44.1 kHz context, on the left
  const r = mixerRig(44100);
  r.send({ t: 'sp', sid: 1, g: 1, p: -1 });
  near(r, 0);
  near(r, 1, { end: true });
  r.step(100);
  const L = r.samples(r.played);
  const Rr = r.samples(r.playedR);
  const nl = L.filter((x) => close(x, R2)).length;
  check('near: 44.1 kHz context: 80 ms on the left, nothing on the right', Math.abs(nl - 3528) <= 2 && Rr.every((x) => Math.abs(x) < 1e-6), `${nl} samples (3528 expected)`);
}

{
  // the probe's levels: left and right apart
  const r = mixerRig();
  r.send({ t: 'cfg', slots: [1, 1, 1, 1], master: 1, deaf: false, probe: true });
  r.send({ t: 'sp', sid: 1, g: 1, p: -1 });
  near(r, 0);
  near(r, 1, { end: true });
  r.ms(200);
  const st = r.stats();
  check('near: probe levels per side (rms left, rmsR right)', st.rms > -25 && st.rmsR < -100, `left ${st.rms && st.rms.toFixed(1)} dB, right ${st.rmsR && st.rmsR.toFixed(1)} dB`);
}

{
  // a mono node (never made by the page): a voice with a place folds into the middle
  const t = thread();
  const m = new t.processors['mv-mixer']();
  const send = (msg) => m.port.onmessage({ data: msg });
  send({ t: 'sp', sid: 1, g: 1, p: -1 });
  send({ t: 'p', sid: 1, slot: 3, seq: 0, end: false, pcm: flat() });
  send({ t: 'p', sid: 1, slot: 3, seq: 1, end: true, pcm: flat() });
  let v = 0;
  for (let i = 0; i < 4; i++) {
    const out = new Float32Array(BLOCK);
    m.process([], [[out]]);
    t.g.currentFrame += BLOCK;
    v = Math.max(v, out[0]);
  }
  check('near: a one-channel output still plays it (half of left + right)', close(v, R2 / 2), v.toFixed(4));
}

{
  // no allocation per block: a centred voice and a voice with a place, steady
  // (the place's scratch block is made once)
  const counter = { n: 0 };
  const r = mixerRig(48000, counter);
  r.send({ t: 'sp', sid: 2, g: 0.7, p: 0.4 });
  const both = (s) => {
    r.frame(s, { sid: 1, slot: 0, pcm: flat(0.1) });
    r.frame(s, { sid: 2, slot: 3, pcm: flat(0.1) });
  };
  for (let s = 0; s < 5; s++) {
    both(s);
    r.ms(40);
  }
  const before = counter.n;
  for (let s = 5; s < 30; s++) {
    both(s);
    r.ms(40);
  }
  const st = r.stats();
  check('near: no Float32Array made per block while two voices play (one with a place)', counter.n === before && st.conceal === 0 && before <= 1, `${counter.n - before} made in 1 s of playback (${before} before)`);
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

{
  // slot 3 (near): push-to-talk and voice activation send on it
  const r = captureRig();
  r.cfg({ tx: 3 });
  r.feed(200, 0.3);
  r.cfg({ tx: -1 });
  r.feed(100, 0.3);
  const f = r.frames();
  const gate = r.posted().find((m) => m.t === 'g' && m.on === 1);
  check('capture: push-to-talk on slot 3', f.length >= 5 && f.every((x) => x.slot === 3) && f[f.length - 1].end === 1 && gate && gate.slot === 3, `${f.length} frames, slots ${[...new Set(f.map((x) => x.slot))].join(',')}`);
  const v = captureRig();
  v.cfg({ vad: true, vadDb: -30, vadSlot: 3 });
  v.feed(400, 0.1);
  v.feed(800, 0.001);
  const g = v.frames();
  check('capture: voice activation frames carry the configured slot (3)', g.length > 0 && g.every((x) => x.slot === 3 && x.vad === 1) && g.filter((x) => x.end).length === 1, `${g.length} frames`);
}

console.log(`${passed} passed, ${failed} failed`);
process.exitCode = failed ? 1 : 0;
