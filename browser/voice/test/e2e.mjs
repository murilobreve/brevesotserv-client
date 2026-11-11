// End-to-end test of the browser voice engine (mythos-voice.js) against a
// local mythos-voz relay, with headless Chromium, its fake microphone playing
// fala.wav, two pages (A talks, B listens) and vozbots. The near step (slot 3,
// stereo places) runs only when the relay's welcome has "near".
//
//   node e2e.mjs [--only ptt,vad,...] [--json report.json]
//
// It starts its own relay (127.0.0.1:7291, no database: rights from tokens
// only) and the test page server (127.0.0.1:8291), and stops both at the end.
// Paths come from the environment:
//   VOZ_RELAY  mythos-voz binary   (default /tmp/qa/voice/bin/mythos-voz)
//   VOZ_MINT   vozmint binary      (default /tmp/qa/voice/bin/vozmint)
//   VOZ_BOT    vozbot binary       (default /tmp/qa/voice/bin/vozbot)
//   VOZ_KEY    key file            (default /tmp/qa/voice/voz.key)
//   VOZ_ROOMS  rooms file          (default ../../../../brevesotserv/tools/voz/voz-rooms.example.json)
//   VOZ_PORT, PAGE_PORT            (7291, 8291)
//   CHROME     browser executable  (default: Playwright's Chromium)
import { spawn, execFile } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { startServer, mint } from './server.mjs';

const require = createRequire(import.meta.url);
let playwright;
try {
  playwright = require('playwright');
} catch (e) {
  playwright = require('/opt/node22/lib/node_modules/playwright');
}
const { chromium } = playwright;

const here = dirname(fileURLToPath(import.meta.url));
const env = process.env;
const RELAY = env.VOZ_RELAY || '/tmp/qa/voice/bin/mythos-voz';
const BOT = env.VOZ_BOT || '/tmp/qa/voice/bin/vozbot';
const KEY = env.VOZ_KEY || '/tmp/qa/voice/voz.key';
const ROOMS = env.VOZ_ROOMS || [join(here, '../../../../brevesotserv/tools/voz/voz-rooms.example.json'), '/home/user/brevesotserv/tools/voz/voz-rooms.example.json'].find(existsSync);
const VOZ_PORT = Number(env.VOZ_PORT || 7291);
const PAGE_PORT = Number(env.PAGE_PORT || 8291);
const WS = `ws://127.0.0.1:${VOZ_PORT}/voz`;
const PAGE = `http://127.0.0.1:${PAGE_PORT}/test/index.html`;
const WAV = join(here, 'fala.wav');
const ROOM = 'p:9:1';
const ROOM2 = 'p:9:2'; // the steps with pages of their own, away from A and B

const args = process.argv.slice(2);
const only = (() => {
  const i = args.indexOf('--only');
  return i >= 0 ? new Set(args[i + 1].split(',')) : null;
})();
const jsonOut = (() => {
  const i = args.indexOf('--json');
  return i >= 0 ? args[i + 1] : null;
})();

const report = { started: new Date().toISOString(), checks: [], measures: {} };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const r1 = (x) => Math.round(x * 10) / 10;

function check(name, ok, detail) {
  report.checks.push({ name, ok: !!ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}  ${typeof detail === 'string' ? detail : JSON.stringify(detail)}`);
}

// --- relay -------------------------------------------------------------------

let relay = null;
const relayLog = [];

function startRelay() {
  relay = spawn(RELAY, ['-listen', '', '-local', `127.0.0.1:${VOZ_PORT}`, '-secret', KEY, '-rooms', ROOMS,
    '-origin', `http://127.0.0.1:${PAGE_PORT}`], { stdio: ['ignore', 'pipe', 'pipe'] });
  const keep = (d) => {
    relayLog.push(...String(d).split('\n').filter(Boolean));
    if (relayLog.length > 400) relayLog.splice(0, relayLog.length - 400);
  };
  relay.stdout.on('data', keep);
  relay.stderr.on('data', keep);
  return waitHealth();
}

async function waitHealth() {
  for (let i = 0; i < 50; i++) {
    try {
      const r = await fetch(`http://127.0.0.1:${VOZ_PORT}/health`);
      if (r.ok) return;
    } catch (e) {
      // not up yet
    }
    await sleep(100);
  }
  throw new Error('relay did not start');
}

function stopRelay(signal = 'SIGTERM') {
  if (!relay) return Promise.resolve();
  const p = relay;
  relay = null;
  return new Promise((resolve) => {
    p.on('exit', resolve);
    p.kill(signal);
    setTimeout(() => {
      try {
        p.kill('SIGKILL');
      } catch (e) {
        // gone
      }
      resolve();
    }, 5000);
  });
}

async function relayStats() {
  const r = await fetch(`http://127.0.0.1:${VOZ_PORT}/stats`);
  return r.json();
}

// --- vozbot ------------------------------------------------------------------

const bots = new Set();

function bot(mode, extra, guid, room = ROOM) {
  const argv = ['-url', WS, '-key', KEY, '-room', room, '-guid', String(guid), ...extra, mode];
  const p = spawn(BOT, argv, { stdio: ['ignore', 'pipe', 'pipe'] });
  const out = [];
  p.stdout.on('data', (d) => out.push(String(d)));
  p.stderr.on('data', (d) => out.push(String(d)));
  p.done = new Promise((resolve) => p.on('exit', (code) => resolve(code)));
  p.output = () => out.join('');
  bots.add(p);
  p.done.then(() => bots.delete(p));
  return p;
}

function execP(cmd, argv) {
  return new Promise((resolve, reject) => execFile(cmd, argv, { maxBuffer: 64 << 20, encoding: 'buffer' }, (err, out, errOut) => (err ? reject(new Error(String(errOut))) : resolve(out))));
}

// RMS envelope (dBFS per 100 ms) of an Opus file, decoded by ffmpeg
async function envelope(file) {
  const raw = await execP('ffmpeg', ['-nostdin', '-loglevel', 'error', '-i', file, '-ac', '1', '-ar', '48000', '-f', 's16le', 'pipe:1']);
  const n = Math.floor(raw.length / 2);
  const win = 4800;
  const out = [];
  for (let i = 0; i + win <= n; i += win) {
    let s = 0;
    for (let k = 0; k < win; k++) {
      const x = raw.readInt16LE((i + k) * 2) / 32768;
      s += x * x;
    }
    out.push(r1(10 * Math.log10(s / win + 1e-12)));
  }
  return out;
}

// --- pages -------------------------------------------------------------------

const claimsA = { a: 11, c: 201, i: 2001, n: 'Ana', p: ROOM, pl: 1, lv: 60, pub: 1 };
const claimsB = { a: 12, c: 202, i: 2002, n: 'Bia', p: ROOM, lv: 60, pub: 1 };
const claimsC = { a: 13, c: 203, i: 2003, n: 'Caio', p: ROOM, lv: 60, pub: 1 };

// opts.init: a script run before the page (browser stand-ins); opts.grant:
// the microphone permission already given to the origin
async function openPage(browser, name, opts = {}) {
  const context = await browser.newContext();
  if (opts.grant) await context.grantPermissions(['microphone'], { origin: new URL(PAGE).origin });
  if (opts.init) await context.addInitScript(opts.init);
  const page = await context.newPage();
  page.on('console', (m) => {
    if (m.type() === 'error' || m.type() === 'warning') console.log(`[${name} console.${m.type()}] ${m.text()}`);
  });
  page.on('pageerror', (e) => {
    console.log(`[${name} pageerror] ${e.message}`);
    report.checks.push({ name: `${name}: no page error`, ok: false, detail: e.message });
  });
  await page.goto(PAGE);
  await page.waitForFunction(() => window.MythosVoice && MythosVoice.support() !== 2, null, { timeout: 10000 });
  const cdp = await context.newCDPSession(page);
  await cdp.send('Performance.enable');
  return { name, context, page, cdp };
}

async function connectPage(p, claims, room = ROOM) {
  const tok = await mint(claims, { key: KEY });
  await p.page.evaluate(([url, t, r]) => harness.connect(url, t, r), [WS, tok, room]);
  await p.page.waitForFunction((r) => harness.welcome && harness.ctl.some((m) => m.t === 'roster' && m.room === r), room, { timeout: 10000 });
  p.sid = await p.page.evaluate(() => harness.welcome.sid);
  return p.sid;
}

const claimsOf = (n, room = ROOM2) => ({ a: 30 + n, c: 230 + n, i: 2030 + n, n: `Extra${n}`, p: room, pl: 1, lv: 60 });

const ev = (p, fn, arg) => p.page.evaluate(fn, arg);
const cmd = (p, c) => p.page.evaluate((x) => MythosVoice.cmd(x), c);
const ctl = (p, m) => p.page.evaluate((x) => harness.send(x), m);
const fresh = (p) => p.page.evaluate(() => MythosVoice.freshStats());
const events = (p, since) => p.page.evaluate((t) => harness.events.filter((e) => e.at >= t), since);
const pageNow = (p) => p.page.evaluate(() => performance.now());
const ctxOf = (p) => p.page.evaluate(() => MythosVoice.stats().ctx);

// the idle sleep: nothing played or captured for 15 s suspends the context
async function waitAsleep(pages, ms = 30000) {
  await Promise.all(pages.map((p) => p.page.waitForFunction(() => MythosVoice.stats().ctx === 'suspended', null, { timeout: ms, polling: 250 }).catch(() => {})));
  return Promise.all(pages.map(ctxOf));
}

// the side mouse button (Back), trusted, through CDP
async function pressBack(p, ms) {
  await p.cdp.send('Input.dispatchMouseEvent', { type: 'mousePressed', button: 'back', buttons: 8, x: 50, y: 50, clickCount: 1 });
  await sleep(ms);
  await p.cdp.send('Input.dispatchMouseEvent', { type: 'mouseReleased', button: 'back', buttons: 0, x: 50, y: 50, clickCount: 1 });
}

async function metrics(p) {
  const { metrics: list } = await p.cdp.send('Performance.getMetrics');
  const m = {};
  for (const x of list) m[x.name] = x.value;
  return m;
}

// --- the steps ---------------------------------------------------------------

const steps = {};
let A;
let B;

// A holds push-to-talk 5 s: frames, END, speaking edges, output RMS, bytes,
// latency; a vozbot records what the relay forwards (interop with libopus)
steps.ptt = async () => {
  await cmd(A, { op: 'probe', on: true });
  await cmd(B, { op: 'probe', on: true });
  await sleep(500);
  const rec = join(work, 'rec-ptt.opus');
  const listener = bot('listen', ['-out', rec, '-dur', '8s'], 901);
  await sleep(800);
  const a0 = await fresh(A);
  const b0 = await fresh(B); // also clears B's mixer RMS window
  const silentB = b0.mix;
  const r0 = await relayStats();
  const tB = await pageNow(B);
  const tA = await pageNow(A);
  await cmd(A, { op: 'tx', slot: 0 });
  await sleep(5000);
  await cmd(A, { op: 'tx', slot: -1 });
  await sleep(1000);
  const a1 = await fresh(A);
  const b1 = await fresh(B);
  const r1s = await relayStats();
  await sleep(1500);
  const a2 = await fresh(A);
  const b2 = await fresh(B);
  const sent = a1.up.f - a0.up.f;
  const got = b1.down.f - b0.down.f;
  check('ptt: A sent ~125 frames in 5 s', Math.abs(sent - 125) <= 6, `${sent} frames`);
  check('ptt: B received 125±5 frames', Math.abs(got - 125) <= 5, `${got} frames`);
  check('ptt: an END frame arrived', b1.down.end - b0.down.end === 1, `${b1.down.end - b0.down.end} END`);
  check('ptt: nothing after release', a2.up.f === a1.up.f && b2.down.f === b1.down.f, `A +${a2.up.f - a1.up.f}, B +${b2.down.f - b1.down.f}`);
  check('ptt: B decoded every frame', b1.down.dec - b0.down.dec >= got - 1 && b1.down.decErr === b0.down.decErr, `dec ${b1.down.dec - b0.down.dec}, errors ${b1.down.decErr - b0.down.decErr}`);
  const rms = b1.mix && b1.mix.rms;
  check('ptt: B output RMS over -45 dBFS', rms > -45, `rms ${r1(rms)} dBFS, peak ${b1.mix && r1(b1.mix.peak)}; silence before: ${silentB && silentB.rms !== undefined ? r1(silentB.rms) : 'n/a'}`);
  const evB = await events(B, tB);
  const spk = evB.filter((e) => e.t === 'spk' && e.a === A.sid);
  check('ptt: speaking on then off at B', spk.length === 2 && spk[0].b === 1 && spk[1].b === 0, spk.map((e) => `${e.b}@${Math.round(e.at - tB)}`).join(' '));
  const evA = await events(A, tA);
  const talk = evA.filter((e) => e.t === 'talk');
  check('ptt: talk 0 then -1 at A', talk.length >= 2 && talk[0].a === 0 && talk[talk.length - 1].a === -1, talk.map((e) => e.a).join(' '));
  const mixB = b1.mix || {};
  report.measures.ptt = { sent, got, conceal: mixB.conceal, late: mixB.late, trimmed: mixB.trimmed, targets: mixB.targets };
  // bytes on the wire: application bytes per talker, relay counters
  const upBps = (a1.up.b - a0.up.b) / 5;
  const downBps = (b1.down.b - b0.down.b) / 5;
  const opusAvg = (b1.down.opus - b0.down.opus) / Math.max(1, got);
  report.measures.bytes = {
    upBytesPerSec: Math.round(upBps), downBytesPerSec: Math.round(downBps), opusAvgBytes: r1(opusAvg),
    opusKbps: r1((opusAvg * 25 * 8) / 1000),
    relayInBytesPerSec: Math.round((r1s.in_bytes - r0.in_bytes) / 5), relayOutBytesPerSec: Math.round((r1s.out_bytes - r0.out_bytes) / 5),
    wireEstimate: 'up = WS payload; on TLS add 6 (WS mask) + 22 (TLS) + 52 (TCP/IP) B per frame',
  };
  check('bytes: Opus about 16 kbps (60-100 B per 40 ms frame)', opusAvg >= 55 && opusAvg <= 100, `${r1(opusAvg)} B/frame, ${Math.round(upBps)} B/s up incl. 3-byte header`);
  // mouth-to-ear: A's capture worklet sees the burst onset; B's mixer plays it
  const capOn = a1.probe.cap.filter((t) => t > performance.timeOrigin - 1e12); // all
  const outOn = b1.probe.out;
  const lats = [];
  for (const t of outOn) {
    const src = capOn.filter((c) => c < t && t - c < 1000).pop();
    if (src) lats.push(Math.round(t - src));
  }
  report.measures.latency = { samplesMs: lats, outputLatencyMsB: b1.lat };
  check('latency: mouth-to-ear on loopback under 250 ms', lats.length >= 2 && Math.max(...lats) < 250, `${lats.join(', ')} ms (B output latency ${b1.lat} ms included)`);
  // the relay's copy, recorded by vozbot through libopus
  await listener.done;
  try {
    const envl = await envelope(rec);
    const loud = envl.filter((d) => d > -30).length;
    const quiet = envl.filter((d) => d < -50).length;
    report.measures.vozbotEnvelope = envl.join(' ');
    check('interop: vozbot (libopus) decodes the browser\'s Opus with the bursts', loud >= 8 && quiet >= 8, `${loud} loud and ${quiet} quiet 100 ms windows of ${envl.length}`);
  } catch (e) {
    check('interop: vozbot recording decodes', false, e.message);
  }
  // the probe keeps the contexts awake: off again, so the steps after this
  // one also run with contexts that may fall asleep, as in the game
  await cmd(A, { op: 'probe', on: false });
  await cmd(B, { op: 'probe', on: false });
};

// voice activation: the gate follows the bursts (0.7 s every 2 s)
steps.vad = async () => {
  await cmd(A, { op: 'vad', db: -40 });
  await cmd(A, { op: 'mode', vad: true });
  await sleep(1500);
  const tA = await pageNow(A);
  const tB = await pageNow(B);
  const b0 = await fresh(B);
  await sleep(8000);
  const b1 = await fresh(B);
  await cmd(A, { op: 'mode', vad: false });
  await sleep(800);
  const evA = await events(A, tA);
  const evB = await events(B, tB);
  const talkOn = evA.filter((e) => e.t === 'talk' && e.a === 0).length;
  const talkOff = evA.filter((e) => e.t === 'talk' && e.a === -1).length;
  const spkOn = evB.filter((e) => e.t === 'spk' && e.a === A.sid && e.b === 1).length;
  const got = b1.down.f - b0.down.f;
  report.measures.vad = { talkOn, talkOff, spkOn, framesIn8s: got, ends: b1.down.end - b0.down.end, opusAvgBytesSpeech: r1((b1.down.opus - b0.down.opus) / Math.max(1, got)) };
  check('vad: the gate opens for each burst (4 in 8 s)', talkOn >= 3 && talkOn <= 5 && talkOff >= 3, `${talkOn} on, ${talkOff} off`);
  check('vad: B hears each spurt (speaking edges, END frames)', spkOn >= 3 && b1.down.end - b0.down.end >= 3, `${spkOn} spk on, ${b1.down.end - b0.down.end} END`);
  check('vad: silence sends nothing (fewer frames than 8 s of talk)', got > 40 && got < 150, `${got} frames in 8 s (200 = always open)`);
};

// self-mute: nothing leaves A, nothing reaches the relay
steps.smute = async () => {
  await cmd(A, { op: 'smute', on: true });
  await ctl(A, { t: 'self', m: 1 });
  const a0 = await fresh(A);
  const r0 = await relayStats();
  await cmd(A, { op: 'tx', slot: 0 });
  await sleep(2000);
  await cmd(A, { op: 'tx', slot: -1 });
  const a1 = await fresh(A);
  const r1s = await relayStats();
  check('self-mute: A sends 0 frames, the relay gets 0', a1.up.f === a0.up.f && r1s.in_msgs === r0.in_msgs, `A +${a1.up.f - a0.up.f}, relay in +${r1s.in_msgs - r0.in_msgs}`);
  await cmd(A, { op: 'smute', on: false });
  await ctl(A, { t: 'self', m: 0 });
  await sleep(300);
};

// mute-for-me: the relay stops forwarding A to B (A still sends)
steps.mute = async () => {
  await ctl(B, { t: 'mute', sid: A.sid, on: 1 });
  await sleep(300);
  const b0 = await fresh(B);
  const r0 = await relayStats();
  await cmd(A, { op: 'tx', slot: 0 });
  await sleep(2000);
  await cmd(A, { op: 'tx', slot: -1 });
  await sleep(500);
  const b1 = await fresh(B);
  const r1s = await relayStats();
  check('mute-for-me: B gets 0 frames of A while the relay receives them', b1.down.m === b0.down.m && r1s.in_msgs - r0.in_msgs >= 45, `B +${b1.down.m - b0.down.m} msgs, relay in +${r1s.in_msgs - r0.in_msgs}`);
  await ctl(B, { t: 'mute', sid: A.sid, on: 0 });
  await sleep(300);
};

// deafen: the relay sends B nothing at all
steps.deaf = async () => {
  await cmd(B, { op: 'deaf', on: true });
  await ctl(B, { t: 'deaf', on: 1 });
  await sleep(300);
  const b0 = await fresh(B);
  await cmd(A, { op: 'tx', slot: 0 });
  await sleep(2000);
  await cmd(A, { op: 'tx', slot: -1 });
  await sleep(500);
  const b1 = await fresh(B);
  check('deafen: B receives 0 audio messages', b1.down.m === b0.down.m, `B +${b1.down.m - b0.down.m}`);
  await cmd(B, { op: 'deaf', on: false });
  await ctl(B, { t: 'deaf', on: 0 });
  await sleep(300);
};

// focus loss releases push-to-talk; the side mouse button talks
steps.blur = async () => {
  const tA = await pageNow(A);
  await cmd(A, { op: 'tx', slot: 0 });
  await sleep(1000);
  await ev(A, () => window.dispatchEvent(new Event('blur')));
  await sleep(300);
  const a0 = await fresh(A);
  await sleep(1000);
  const a1 = await fresh(A);
  const evA = await events(A, tA);
  check('blur: push-to-talk released (talk -1, no more frames)', evA.some((e) => e.t === 'talk' && e.a === -1) && a1.up.f === a0.up.f, `+${a1.up.f - a0.up.f} frames after blur`);
  await cmd(A, { op: 'pttMouse', btn: 3, slot: 0 });
  const m0 = await fresh(A);
  const prevented = await ev(A, () => {
    const down = new MouseEvent('mousedown', { button: 3, bubbles: true, cancelable: true });
    document.body.dispatchEvent(down);
    return down.defaultPrevented;
  });
  await sleep(1200);
  const prevented2 = await ev(A, () => {
    const up = new MouseEvent('mouseup', { button: 3, bubbles: true, cancelable: true });
    document.body.dispatchEvent(up);
    const aux = new MouseEvent('auxclick', { button: 3, bubbles: true, cancelable: true });
    document.body.dispatchEvent(aux);
    return up.defaultPrevented && aux.defaultPrevented;
  });
  await sleep(300);
  const m1 = await fresh(A);
  await sleep(600);
  const m2 = await fresh(A);
  check('mouse button 4 (Back): talks while held, browser default prevented', m1.up.f - m0.up.f >= 25 && m2.up.f === m1.up.f && prevented && prevented2, `${m1.up.f - m0.up.f} frames, +${m2.up.f - m1.up.f} after release`);
  await cmd(A, { op: 'pttMouse', btn: 0, slot: -1 });
};

// "Testar microfone": local loopback through the codec, nothing on the wire
steps.test = async () => {
  await cmd(A, { op: 'probe', on: true }); // the mixer's RMS
  const a0 = await fresh(A);
  await cmd(A, { op: 'test', on: true });
  await sleep(2500);
  const a1 = await fresh(A);
  await cmd(A, { op: 'test', on: false });
  await cmd(A, { op: 'probe', on: false });
  check('mic test: A hears itself, sends nothing', a1.mix && a1.mix.rms > -45 && a1.up.f === a0.up.f, `rms ${a1.mix && r1(a1.mix.rms)} dBFS, sent +${a1.up.f - a0.up.f}`);
};

// eco preset: 60 ms frames, mixed with 40 ms ones in the same room
steps.eco = async () => {
  await cmd(A, { op: 'preset', p: 1 });
  const b0 = await fresh(B);
  await cmd(A, { op: 'tx', slot: 0 });
  await sleep(3000);
  await cmd(A, { op: 'tx', slot: -1 });
  await sleep(700);
  const b1 = await fresh(B);
  const got = b1.down.f - b0.down.f;
  const avg = (b1.down.opus - b0.down.opus) / Math.max(1, got);
  check('eco: 60 ms frames (~50 in 3 s), decoded', Math.abs(got - 50) <= 4 && b1.down.dec - b0.down.dec >= got - 1, `${got} frames, ${r1(avg)} B avg`);
  await cmd(A, { op: 'preset', p: 0 });
};

// five talkers: B hears at most 4 (last-N) and is told "over"
steps.lastn = async () => {
  const tB = await pageNow(B);
  const talkers = [];
  for (let i = 0; i < 4; i++) talkers.push(bot('talk', ['-in', WAV, '-loop', '1'], 910 + i));
  await sleep(1500);
  await cmd(A, { op: 'tx', slot: 0 });
  await sleep(4000);
  const b1 = await fresh(B);
  await cmd(A, { op: 'tx', slot: -1 });
  await Promise.all(talkers.map((t) => t.done));
  const evB = await events(B, tB);
  const sids = new Set(evB.filter((e) => e.t === 'spk' && e.b === 1).map((e) => e.a));
  const over = (await ev(B, (t) => harness.ctl.filter((m) => m.t === 'over' && m.at >= t), tB)).map((m) => m.n);
  report.measures.lastn = { speakingSids: [...sids], over, decoders: b1.decoders, mixerSpeakers: b1.mix && b1.mix.speakers };
  check('last-N: B hears 4 of the 5 talkers and gets over n>=1', sids.size === 4 && over.some((n) => n >= 1), `${sids.size} speaking sids, over ${JSON.stringify(over)}, ${b1.decoders} decoders`);
  const rs = await relayStats();
  report.measures.lastn.relayLastnDrops = rs.drops.lastn;
};

// CPU and memory of both pages: idle (connected, nobody talking), then A
// talking to B
steps.cpu = async () => {
  const win = 10;
  const sample = async () => {
    const [ma, mb] = await Promise.all([metrics(A), metrics(B)]);
    return { ma, mb, t: Date.now() };
  };
  const cpuOf = (x, y) => ({
    mainA: r1((100 * (y.ma.TaskDuration - x.ma.TaskDuration)) / ((y.t - x.t) / 1000)),
    mainB: r1((100 * (y.mb.TaskDuration - x.mb.TaskDuration)) / ((y.t - x.t) / 1000)),
    heapA_MB: r1(y.ma.JSHeapUsedSize / 1e6),
    heapB_MB: r1(y.mb.JSHeapUsedSize / 1e6),
  });
  const procs = async () => {
    const { processInfo } = await browserCdp.send('SystemInfo.getProcessInfo');
    return processInfo;
  };
  const procCpu = (p0, p1, secs) => {
    const out = {};
    for (const p of p1) {
      const q = p0.find((x) => x.id === p.id);
      if (q) out[`${p.type}:${p.id}`] = r1((100 * (p.cpuTime - q.cpuTime)) / secs);
    }
    return out;
  };
  await cmd(A, { op: 'probe', on: false });
  await cmd(B, { op: 'probe', on: false });
  await sleep(17000); // past the idle suspend (15 s)
  const sa = await fresh(A);
  const sb = await fresh(B);
  let x = await sample();
  let p0 = await procs();
  await sleep(win * 1000);
  let y = await sample();
  let p1 = await procs();
  const idle = { ...cpuOf(x, y), ctxA: sa.ctx, ctxB: sb.ctx, processes: procCpu(p0, p1, win) };
  await cmd(A, { op: 'tx', slot: 0 });
  await sleep(1000);
  x = await sample();
  p0 = await procs();
  await sleep(win * 1000);
  y = await sample();
  p1 = await procs();
  await cmd(A, { op: 'tx', slot: -1 });
  const talking = { ...cpuOf(x, y), processes: procCpu(p0, p1, win) };
  report.measures.cpu = { idle, talking, note: 'main = page main thread (CDP TaskDuration); processes = whole renderer / audio service, all threads, % of one core' };
  check('cpu: page main thread under 5% while talking/listening', talking.mainA < 5 && talking.mainB < 5, `A ${talking.mainA}%, B ${talking.mainB}% (idle A ${idle.mainA}%, B ${idle.mainB}%)`);
  check('memory: JS heap small', talking.heapA_MB < 15 && talking.heapB_MB < 15, `A ${talking.heapA_MB} MB, B ${talking.heapB_MB} MB`);
  check('idle: the audio context sleeps when nobody talks', idle.ctxA === 'suspended' && idle.ctxB === 'suspended', `A ${idle.ctxA}, B ${idle.ctxB}`);
};

// The settings window sends every setting again on each slider step or
// checkbox (voice.lua applyEnginePrefs): nothing may restart. The microphone
// stays open, the meter keeps its level, a spurt in progress goes on; only a
// real device change reopens the microphone, once.
const prefsBurst = (outvol) => [
  { op: 'mode', vad: false }, { op: 'vad', db: -45 }, { op: 'preset', p: 0 }, { op: 'ingain', x: 1 }, { op: 'outvol', x: outvol },
  { op: 'smute', on: false }, { op: 'deaf', on: false }, { op: 'indev', id: '' }, { op: 'outdev', id: '' }, { op: 'pttMouse', btn: 0, slot: -1 },
];
const burst = (p, list) => ev(p, (l) => l.forEach((c) => MythosVoice.cmd(c)), list);

steps.prefs = async () => {
  // the microphone open, as after a first press (the meter alone does not ask)
  await cmd(A, { op: 'test', on: true });
  await sleep(700);
  await cmd(A, { op: 'test', on: false });
  await cmd(A, { op: 'meter', on: true });
  await sleep(600);
  let t0 = await pageNow(A);
  for (let i = 0; i < 10; i++) {
    await burst(A, prefsBurst(0.5 + i / 20));
    await sleep(100);
  }
  await burst(A, prefsBurst(1));
  await sleep(1000);
  let e = await events(A, t0);
  const mics = e.filter((x) => x.t === 'mic').map((x) => x.s);
  const levels = e.filter((x) => x.t === 'level').length;
  const span = Math.round((await pageNow(A)) - t0);
  check('prefs: 10 setting bursts (a slider drag) keep the microphone open and the meter going', mics.length === 0 && levels >= span / 100 - 3,
    `mic events ${JSON.stringify(mics)}, ${levels} levels in ${span} ms`);
  await cmd(A, { op: 'meter', on: false });
  const b0 = await fresh(B);
  const tB = await pageNow(B);
  await cmd(A, { op: 'tx', slot: 0 });
  await sleep(800);
  for (let i = 0; i < 3; i++) {
    await burst(A, prefsBurst(1));
    await sleep(400);
  }
  await sleep(500);
  await cmd(A, { op: 'tx', slot: -1 });
  await sleep(800);
  const b1 = await fresh(B);
  const spk = (await events(B, tB)).filter((x) => x.t === 'spk' && x.a === A.sid);
  check('prefs: setting bursts while talking keep one spurt at B', spk.length === 2 && b1.down.end - b0.down.end === 1,
    `${spk.length} spk edges, ${b1.down.end - b0.down.end} END, ${b1.down.f - b0.down.f} frames`);
  // another device, then back to the default: one reopen each
  const names = await ev(A, () => (harness.events.filter((x) => x.t === 'devices').pop() || { i: [] }).i);
  const other = names[0] || 'a device that is gone';
  t0 = await pageNow(A);
  await cmd(A, { op: 'meter', on: true });
  await burst(A, [{ op: 'indev', id: other }, { op: 'indev', id: other }]);
  await sleep(1500);
  const m1 = (await events(A, t0)).filter((x) => x.t === 'mic').map((x) => x.s);
  await burst(A, [{ op: 'indev', id: '' }, { op: 'indev', id: '' }]);
  await sleep(1500);
  const m2 = (await events(A, t0)).filter((x) => x.t === 'mic').map((x) => x.s);
  await cmd(A, { op: 'meter', on: false });
  check('prefs: a real input device change reopens the microphone once', JSON.stringify(m1) === '["ok"]' && JSON.stringify(m2) === '["ok","ok"]',
    `to ${JSON.stringify(other)}: ${JSON.stringify(m1)}; back to default: ${JSON.stringify(m2)} (of ${names.length} names)`);
};

// getUserMedia, counted (the page's own calls)
const countGum = () => {
  window.__gum = 0;
  const md = navigator.mediaDevices;
  const real = md.getUserMedia.bind(md);
  md.getUserMedia = (c) => {
    window.__gum++;
    return real(c);
  };
};

// The level meter (on while the settings window is open) never asks for the
// microphone: with no permission yet it waits for a press (the mic test,
// push-to-talk); with the permission given it opens it at once.
steps.meterperm = async () => {
  const C = await openPage(mainBrowser, 'C', { init: countGum });
  await cmd(C, { op: 'meter', on: true });
  await sleep(2500); // a housekeeping tick or two
  const g0 = await ev(C, () => window.__gum);
  const lv0 = (await events(C, 0)).filter((e) => e.t === 'level').length;
  const perm = (await fresh(C)).perm;
  check('meter: settings opened without the permission: no microphone request', g0 === 0 && lv0 === 0, `permission ${perm}, getUserMedia ${g0}, levels ${lv0}`);
  await cmd(C, { op: 'test', on: true });
  await sleep(1500);
  await cmd(C, { op: 'test', on: false });
  await sleep(1000);
  const g1 = await ev(C, () => window.__gum);
  const lv1 = (await events(C, 0)).filter((e) => e.t === 'level').length;
  check('meter: the mic test (a press) opens it once, then the meter shows the level', g1 === 1 && lv1 >= 15, `getUserMedia ${g1}, levels ${lv1}`);
  await cmd(C, { op: 'meter', on: false });
  await C.context.close();
  const D = await openPage(mainBrowser, 'D', { init: countGum, grant: true });
  await D.page.waitForFunction(() => MythosVoice.stats().perm === 'granted', null, { timeout: 5000 }).catch(() => {});
  await cmd(D, { op: 'meter', on: true });
  await sleep(1500);
  const g2 = await ev(D, () => window.__gum);
  const lv2 = (await events(D, 0)).filter((e) => e.t === 'level').length;
  check('meter: with the permission given, the meter opens the microphone at once', g2 === 1 && lv2 >= 8, `permission ${(await fresh(D)).perm}, getUserMedia ${g2}, levels ${lv2}`);
  await cmd(D, { op: 'meter', on: false });
  await D.context.close();
};

// an encoder that refuses some settings asynchronously, as configure() does
// with a codec it cannot make (NotSupportedError, then closed)
const refuseEncoder = (which) => {
  const Real = window.AudioEncoder;
  window.__enc = 0;
  window.AudioEncoder = class extends Real {
    constructor(init) {
      super(init);
      window.__enc++;
    }
    configure(cfg) {
      const refuse = which === 'all' || (cfg.opus && cfg.opus.frameDuration === 60000);
      return super.configure(refuse ? { ...cfg, codec: 'not-a-codec' } : cfg);
    }
  };
  window.AudioEncoder.isConfigSupported = Real.isConfigSupported.bind(Real); // says yes, as a browser that lies
};

steps.encfail = async () => {
  // eco refused: one failure, then the normal preset (40 ms) for this page
  const C = await openPage(mainBrowser, 'C', { init: `(${refuseEncoder})('eco')` });
  await connectPage(C, claimsOf(1), ROOM2);
  const listener = bot('listen', ['-dur', '5s'], 940, ROOM2);
  await sleep(500);
  const r0 = await relayStats();
  await cmd(C, { op: 'preset', p: 1 });
  await cmd(C, { op: 'tx', slot: 0 });
  await sleep(3000);
  await cmd(C, { op: 'tx', slot: -1 });
  await sleep(600);
  const r1s = await relayStats();
  const c1 = await fresh(C);
  const made = await ev(C, () => window.__enc);
  const ev1 = await events(C, 0);
  const caps = ev1.filter((e) => e.t === 'caps').map((e) => JSON.parse(e.s).presets);
  const encEv = ev1.filter((e) => e.t === 'mic' && e.s === 'encoder').length;
  check('encoder: eco refused -> normal frames for the rest, not a new encoder per frame',
    made <= 3 && c1.up.f >= 60 && c1.up.presets[1] === 0 && encEv === 0 && r1s.in_msgs - r0.in_msgs >= 60,
    `${made} encoders, sent ${c1.up.f}, relay in +${r1s.in_msgs - r0.in_msgs}, encErr ${c1.up.encErr}, caps presets ${JSON.stringify(caps)}, encoder events ${encEv}`);
  await listener.done;
  await C.context.close();
  // nothing encodes: retried every 2 s, one 'encoder' event, nothing sent
  const D = await openPage(mainBrowser, 'D', { init: `(${refuseEncoder})('all')` });
  await connectPage(D, claimsOf(2), ROOM2);
  await cmd(D, { op: 'tx', slot: 0 });
  await sleep(5000);
  await cmd(D, { op: 'tx', slot: -1 });
  await sleep(300);
  const d1 = await fresh(D);
  const madeD = await ev(D, () => window.__enc);
  const encD = (await events(D, 0)).filter((e) => e.t === 'mic' && e.s === 'encoder').length;
  check('encoder: none works -> one try per 2 s, one "encoder" event, nothing sent', madeD >= 2 && madeD <= 4 && encD === 1 && d1.up.f === 0 && d1.errors === 0,
    `${madeD} encoders in 5 s, ${encD} encoder events, sent ${d1.up.f}, encErr ${d1.up.encErr}, errors ${d1.errors} ${d1.lastError}`);
  await D.context.close();
};

// A browser that starts audio only inside a press (WebKit), stricter than
// Chrome before any activation: resume() outside a trusted pointerdown or
// keydown stays pending for ever. Playwright's evaluate counts as a gesture
// for navigator.userActivation, so the stand-in tracks trusted events itself.
const strictAudio = () => {
  const R = window.AudioContext;
  let inPress = false;
  const press = (e) => {
    if (e.isTrusted) {
      inPress = true;
      setTimeout(() => {
        inPress = false;
      }, 0);
    }
  };
  window.addEventListener('pointerdown', press, true);
  window.addEventListener('keydown', press, true);
  window.__resume = { calls: 0, allowed: 0 };
  window.AudioContext = class extends R {
    constructor(o) {
      super(o);
      R.prototype.suspend.call(this); // not allowed to start
    }
    resume() {
      window.__resume.calls++;
      if (inPress) {
        window.__resume.allowed++;
        return R.prototype.resume.call(this);
      }
      return new Promise(() => {});
    }
  };
};

steps.gesture = async () => {
  const C = await openPage(mainBrowser, 'C', { init: strictAudio });
  await connectPage(C, claimsOf(3), ROOM2);
  let talker = bot('talk', ['-in', WAV], 941, ROOM2);
  await sleep(3000); // past WAKE_CHECK_MS, frames arriving
  // frames played by the mixer (it plays only while the context runs)
  const played = (x) => (x.mix && x.mix.played) || 0;
  const s0 = await fresh(C);
  check('gesture: before any press the context waits (frames arrive, nothing plays)', s0.ctx !== 'running' && s0.down.f > 20 && played(s0) === 0,
    `ctx ${s0.ctx}, ${s0.down.f} frames in, ${played(s0)} played, resume calls ${JSON.stringify(await ev(C, () => window.__resume))}`);
  await C.page.mouse.click(5, 5);
  await sleep(2000);
  const s1 = await fresh(C);
  check('gesture: one click resumes it although the first resume() is still pending', s1.ctx === 'running' && played(s1) > 20,
    `ctx ${s1.ctx}, ${played(s1)} frames played, resume ${JSON.stringify(await ev(C, () => window.__resume))}, wake ${JSON.stringify(s1.wake)}`);
  await talker.done;
  await sleep(17000); // past the idle sleep (15 s)
  const s2 = await fresh(C);
  talker = bot('talk', ['-in', WAV], 942, ROOM2);
  await sleep(2500);
  const s3 = await fresh(C);
  check('gesture: there it never sleeps, so the next voice after an idle time plays with no press',
    s2.ctx === 'running' && s2.wake.needPress && s3.ctx === 'running' && played(s3) - played(s2) > 20,
    `after 17 s idle ctx ${s2.ctx}, needPress ${s2.wake.needPress}; next voice: ${played(s3) - played(s2)} frames played`);
  talker.kill('SIGKILL');
  await C.context.close();
};

// Chrome after the "Jogar" click: the context sleeps when idle and an
// incoming voice wakes it on its own (no press)
steps.wake = async () => {
  // its own preconditions (any order, --only): no probe, B asleep
  await cmd(A, { op: 'probe', on: false });
  await cmd(B, { op: 'probe', on: false });
  await waitAsleep([B]);
  const slept = (await fresh(B)).ctx;
  const abs0 = await ev(B, () => performance.timeOrigin + performance.now());
  await cmd(A, { op: 'probe', on: true });
  await cmd(B, { op: 'probe', on: true });
  await sleep(300);
  await cmd(A, { op: 'tx', slot: 0 });
  await sleep(2500);
  await cmd(A, { op: 'tx', slot: -1 });
  await sleep(600);
  const a1 = await fresh(A);
  const b1 = await fresh(B);
  await cmd(A, { op: 'probe', on: false });
  await cmd(B, { op: 'probe', on: false });
  const lats = [];
  for (const t of b1.probe.out) {
    const src = a1.probe.cap.filter((c) => c < t && t - c < 1000).pop();
    if (src && t >= abs0) lats.push(Math.round(t - src));
  }
  check('wake: B asleep when idle, woken by A\'s voice with no press', slept === 'suspended' && b1.mix && b1.mix.rms > -45 && !b1.wake.needPress,
    `B ${slept} before, rms ${b1.mix && r1(b1.mix.rms)} dBFS, needPress ${b1.wake.needPress}, mouth-to-ear after the sleep ${lats.slice(0, 3).join(', ')} ms`);
  report.measures.wakeLatencyMs = lats;
};

// After the idle sleep (15 s with nothing played or captured the context is
// suspended, and the capture worklet does not run in a suspended context),
// every way of using the microphone still works: the mic test, the level
// meter, switching to voice activation, unmuting in voice activation, the
// side mouse button. One page per case, each alone in its own room, so that
// no case wakes another with its voice; all sleep together, then each is
// checked in turn. Frames are counted at the page and at the relay.
steps.asleep = async () => {
  const mk = async (name, n, opts) => {
    const p = await openPage(mainBrowser, name, opts);
    p.room = `p:9:${20 + n}`;
    return p;
  };
  const T = await mk('T', 1);
  const M = await mk('M', 2);
  const V = await mk('V', 3);
  const U = await mk('U', 4);
  const K = await mk('K', 5);
  const all = [T, M, V, U, K];
  try {
    await cmd(U, { op: 'vad', db: -40 });
    await cmd(U, { op: 'mode', vad: true }); // the saved mode, sent before connect
    for (const [i, p] of all.entries()) await connectPage(p, claimsOf(10 + i, p.room), p.room);
    await cmd(M, { op: 'tx', slot: 0 }); // a first press opens the microphone
    await sleep(600);
    await cmd(M, { op: 'tx', slot: -1 });
    await cmd(K, { op: 'pttMouse', btn: 3, slot: 0 });
    await sleep(4000);
    const u0 = await fresh(U);
    await cmd(U, { op: 'smute', on: true });
    await ctl(U, { t: 'self', m: 1 });
    const slept = await waitAsleep(all);
    const sends = async (p, fn) => {
      const a = await fresh(p);
      const r0 = await relayStats();
      await fn();
      const b = await fresh(p);
      const r1s = await relayStats();
      return { sent: b.up.f - a.up.f, relay: r1s.in_msgs - r0.in_msgs, bad: (r1s.drops.bad || 0) - (r0.drops.bad || 0), ctx: b.ctx, mic: b.mic, after: b };
    };
    report.measures.asleep = { slept: Object.fromEntries(all.map((p, i) => [p.name, slept[i]])), vadAtConnect: u0.up.f };
    // 1. "Testar microfone", no microphone opened before on this page
    const t0 = await fresh(T);
    await cmd(T, { op: 'test', on: true });
    await sleep(1200);
    const t1 = await fresh(T); // the mixer plays (and counts) only in a running context
    await cmd(T, { op: 'probe', on: true }); // then its RMS (the probe alone would keep it awake)
    await sleep(1500);
    const t2 = await fresh(T);
    await cmd(T, { op: 'test', on: false });
    await cmd(T, { op: 'probe', on: false });
    const playedT = ((t1.mix && t1.mix.played) || 0) - ((t0.mix && t0.mix.played) || 0);
    check('asleep: the mic test plays the microphone back', slept[0] === 'suspended' && t1.ctx === 'running' && playedT > 15 && t2.mix && t2.mix.rms > -45,
      `before ${slept[0]}; 1.2 s into the test: ctx ${t1.ctx}, mic ${t1.mic}, ${playedT} frames played; then rms ${t2.mix && r1(t2.mix.rms)} dBFS`);
    // 2. the level meter (settings window opened)
    const tm = await pageNow(M);
    await cmd(M, { op: 'meter', on: true });
    await sleep(2000);
    const lv = (await events(M, tm)).filter((e) => e.t === 'level').length;
    const m1 = await fresh(M);
    await cmd(M, { op: 'meter', on: false });
    check('asleep: the level meter shows the level', slept[1] === 'suspended' && lv >= 15, `before ${slept[1]}; ${lv} levels in 2 s, ctx ${m1.ctx}, mic ${m1.mic}`);
    // 3. switching to voice activation
    const v = await sends(V, async () => {
      await cmd(V, { op: 'vad', db: -40 });
      await cmd(V, { op: 'mode', vad: true });
      await sleep(6000);
    });
    await cmd(V, { op: 'mode', vad: false });
    check('asleep: switching to voice activation transmits', slept[2] === 'suspended' && v.sent > 20 && v.relay >= v.sent - 2 && v.bad === 0,
      `before ${slept[2]}; in 6 s: sent ${v.sent}, relay in +${v.relay}, dropped bad +${v.bad}, ctx ${v.ctx}, mic ${v.mic}`);
    // 4. unmuting in voice activation after a long self-mute
    const u = await sends(U, async () => {
      await cmd(U, { op: 'smute', on: false });
      await ctl(U, { t: 'self', m: 0 });
      await sleep(6000);
    });
    await cmd(U, { op: 'mode', vad: false });
    check('asleep: voice activation transmits again after a self-mute longer than the sleep', u0.up.f > 15 && slept[3] === 'suspended' && u.sent > 20 && u.relay >= u.sent - 2,
      `at connect ${u0.up.f} frames in 4 s; muted: ${slept[3]}; 6 s after the unmute: sent ${u.sent}, relay in +${u.relay}, ctx ${u.ctx}, mic ${u.mic}`);
    // 5. the side mouse button (trusted events)
    const k = await sends(K, async () => {
      await pressBack(K, 2000);
      await sleep(400);
    });
    check('asleep: the side mouse button talks', slept[4] === 'suspended' && k.sent > 25 && k.relay >= k.sent - 2, `before ${slept[4]}; 2 s held: sent ${k.sent}, relay in +${k.relay}, ctx ${k.ctx}`);
    // the key held while the mouse button goes down and up: the key goes on
    await cmd(K, { op: 'tx', slot: 0 });
    await sleep(800);
    await pressBack(K, 600);
    await sleep(300);
    const kk = await sends(K, () => sleep(2000));
    await cmd(K, { op: 'tx', slot: -1 });
    check('push-to-talk key held across the mouse button: still talking after the button is let go', kk.sent >= 45 && kk.after.tx === 0,
      `${kk.sent} frames in the 2 s after the button came up (tx ${kk.after.tx})`);
    const errs = (await Promise.all(all.map(fresh))).map((x, i) => `${all[i].name} ${x.errors} ${x.lastError}`).filter((x) => !/ 0 $/.test(x));
    check('asleep: no engine error on the five pages', errs.length === 0, errs.join('; ') || 'none');
  } finally {
    for (const p of all) await p.context.close();
  }
};

// voice activation in no room: the microphone stays closed, nothing goes up,
// no 'talk'; once a room is joined it opens and the voice goes there
steps.vadroom = async () => {
  const room = 'p:9:30';
  const N = await openPage(mainBrowser, 'N', { init: countGum });
  try {
    const tok = await mint(claimsOf(20, room), { key: KEY });
    await N.page.evaluate(([u, t]) => harness.connect(u, t, null), [WS, tok]); // no join
    await N.page.waitForFunction(() => !!harness.welcome, null, { timeout: 10000 });
    const t0 = await pageNow(N);
    const r0 = await relayStats();
    await cmd(N, { op: 'vad', db: -40 });
    await cmd(N, { op: 'mode', vad: true });
    await sleep(5000);
    const n1 = await fresh(N);
    const r1s = await relayStats();
    const talk1 = (await events(N, t0)).filter((e) => e.t === 'talk').length;
    const gum1 = await ev(N, () => window.__gum);
    check('vad in no room: microphone closed, nothing sent, no talk event', n1.up.f === 0 && talk1 === 0 && gum1 === 0 && r1s.in_msgs === r0.in_msgs,
      `rooms ${JSON.stringify(n1.rooms)}, mic ${n1.mic}, getUserMedia ${gum1}, sent ${n1.up.f}, talk ${talk1}, relay in +${r1s.in_msgs - r0.in_msgs}`);
    await ctl(N, { t: 'join', room });
    await sleep(5000);
    const n2 = await fresh(N);
    const r2 = await relayStats();
    const talk2 = (await events(N, t0)).filter((e) => e.t === 'talk' && e.a === 0).length;
    check('vad: joining a room opens the microphone and the voice goes up', n2.up.f > 20 && talk2 >= 1 && (r2.drops.bad || 0) === (r1s.drops.bad || 0),
      `rooms ${JSON.stringify(n2.rooms)}, mic ${n2.mic}, sent ${n2.up.f}, talk on ${talk2}, dropped bad +${(r2.drops.bad || 0) - (r1s.drops.bad || 0)}`);
    await cmd(N, { op: 'mode', vad: false });
  } finally {
    await N.context.close();
  }
};

// A browser that lists no labels (nor ids) before the first getUserMedia of
// the page (Chrome without a stored permission, Firefox): the saved input
// and output devices are still the ones used, once the labels show.
const hideLabels = () => {
  const md = navigator.mediaDevices;
  const realEnum = md.enumerateDevices.bind(md);
  const realGum = md.getUserMedia.bind(md);
  let opened = false;
  window.__gum = [];
  md.getUserMedia = (c) => realGum(c).then((s) => {
    opened = true;
    const tr = s.getAudioTracks()[0];
    window.__gum.push({ want: JSON.stringify((c.audio && c.audio.deviceId) || null), got: tr && tr.label });
    return s;
  });
  md.enumerateDevices = () => realEnum().then((list) => (opened ? list : list.filter((d, i, a) => a.findIndex((x) => x.kind === d.kind) === i).map((d) => ({ deviceId: '', groupId: '', kind: d.kind, label: '' }))));
};

// a microphone missing at first ('nodevice'), plugged in later
const lateMic = () => {
  const md = navigator.mediaDevices;
  const realGum = md.getUserMedia.bind(md);
  window.__noMic = true;
  window.__gum = 0;
  md.getUserMedia = (c) => {
    window.__gum++;
    return window.__noMic ? Promise.reject(new DOMException('Requested device not found', 'NotFoundError')) : realGum(c);
  };
};

steps.devices = async () => {
  // 1. saved devices, labels hidden until the first open
  const H = await openPage(mainBrowser, 'H', { init: hideLabels });
  try {
    await connectPage(H, claimsOf(21, 'p:9:31'), 'p:9:31');
    await cmd(H, { op: 'indev', id: 'Fake Audio Input 1' }); // what the settings saved last session
    await cmd(H, { op: 'outdev', id: 'Fake Audio Output 1' });
    const before = await fresh(H);
    await cmd(H, { op: 'tx', slot: 0 });
    await sleep(2500);
    const mid = await fresh(H);
    await cmd(H, { op: 'tx', slot: -1 });
    await sleep(500);
    const gum = await ev(H, () => window.__gum);
    const outId = await ev(H, () => navigator.mediaDevices.enumerateDevices().then((l) => (l.find((d) => d.label === 'Fake Audio Output 1') || {}).deviceId || ''));
    const h1 = await fresh(H);
    check('devices: no labels before the first open: the microphone moves to the saved device, once', gum.length === 2 && gum[1].got === 'Fake Audio Input 1' && h1.micMoves === 1 && mid.up.f - before.up.f > 30,
      `getUserMedia ${JSON.stringify(gum)}, moves ${h1.micMoves}, sent ${mid.up.f - before.up.f} in 2.5 s`);
    check('devices: ...and the saved output device is used once it has an id', !!outId && h1.sinkId === outId, `sinkId ${JSON.stringify(h1.sinkId)} (want ${JSON.stringify(outId)})`);
  } finally {
    await H.context.close();
  }
  // 2. voice activation, the microphone missing, then plugged in
  const L2 = await openPage(mainBrowser, 'L2', { init: lateMic });
  try {
    await cmd(L2, { op: 'vad', db: -40 });
    await cmd(L2, { op: 'mode', vad: true });
    await connectPage(L2, claimsOf(22, 'p:9:32'), 'p:9:32');
    await L2.page.waitForFunction(() => MythosVoice.stats().mic === 'nodevice', null, { timeout: 5000 }).catch(() => {});
    const a = await fresh(L2);
    const t0 = await pageNow(L2);
    await ev(L2, () => {
      window.__noMic = false;
      navigator.mediaDevices.dispatchEvent(new Event('devicechange'));
    });
    await sleep(4000);
    const b = await fresh(L2);
    const mics = (await events(L2, t0)).filter((e) => e.t === 'mic').map((e) => e.s);
    check('devices: voice activation picks up a microphone plugged in later', a.mic === 'nodevice' && b.mic === 'on' && mics[0] === 'ok' && b.up.f > 15,
      `before ${a.mic}, after the devicechange ${b.mic} (events ${JSON.stringify(mics)}), sent ${b.up.f} in 4 s, getUserMedia ${await ev(L2, () => window.__gum)}`);
  } finally {
    await L2.context.close();
  }
  // 3. the settings window open while the game drops the connection: the
  // meter goes on (the game sends 'meter' only when the window opens)
  const W = await openPage(mainBrowser, 'W', { grant: true });
  try {
    await connectPage(W, claimsOf(23, 'p:9:33'), 'p:9:33');
    await W.page.waitForFunction(() => MythosVoice.stats().perm === 'granted', null, { timeout: 5000 }).catch(() => {});
    await cmd(W, { op: 'meter', on: true });
    await sleep(1500);
    const t0 = await pageNow(W);
    await ev(W, () => harness.disconnect());
    await sleep(2500);
    const lv = (await events(W, t0 + 300)).filter((e) => e.t === 'level').length;
    // the window closes while not connected: the microphone goes after 30 s
    // (5 min is for push-to-talk while connected)
    await cmd(W, { op: 'meter', on: false });
    const tOff = Date.now();
    await W.page.waitForFunction(() => MythosVoice.stats().mic === 'off', null, { timeout: 45000, polling: 500 }).catch(() => {});
    const offAfter = Math.round((Date.now() - tOff) / 1000);
    const wOff = await fresh(W);
    await cmd(W, { op: 'meter', on: true });
    await sleep(1500);
    const t1 = await pageNow(W);
    await cmd(W, { op: 'disconnect', end: true }); // the game closing
    await sleep(1500);
    const lv2 = (await events(W, t1 + 300)).filter((e) => e.t === 'level').length;
    const w = await fresh(W);
    check('devices: the meter goes on after a disconnect, and stops when the game ends', lv >= 12 && lv2 === 0 && w.mic === 'off',
      `${lv} levels in the 2.2 s after the disconnect; after the end: ${lv2} levels, mic ${w.mic}, ctx ${w.ctx}`);
    check('devices: not connected, the microphone the meter used goes 30 s after the window closes', wOff.mic === 'off' && offAfter >= 28 && offAfter <= 35,
      `mic ${wOff.mic} after ${offAfter} s`);
  } finally {
    await W.context.close();
  }
};

// the relay restarts: closed 1012, backoff while it is down, then online
// again; the engine itself never reconnects
steps.restart = async () => {
  for (const [p, claims] of [[A, claimsA], [B, claimsB]]) {
    await ev(p, ([url, c, r]) => {
      harness.disconnect();
      harness.autoReconnect(url, c, r);
    }, [WS, claims, ROOM]);
  }
  // the new session of autoReconnect is up (not the old welcome/roster)
  for (const p of [A, B]) {
    await p.page.waitForFunction((r) => harness.joinedSince(harness.reconnect.since, r), ROOM, { timeout: 10000 });
  }
  const s0 = await Promise.all([fresh(A), fresh(B)]);
  const n0 = await Promise.all([A, B].map((p) => ev(p, () => harness.reconnect.attempts.length)));
  const t0 = await Promise.all([pageNow(A), pageNow(B)]);
  await stopRelay('SIGTERM');
  const downFor = 9000;
  await sleep(downFor);
  await startRelay();
  // online again: the Lua-side backoff (1, 2, 4, 8, 16 s, +-30 %) may take
  // up to ~20 s after the relay is back, so wait for it instead of a fixed time
  for (const [i, p] of [A, B].entries()) {
    await p.page.waitForFunction(([t, r]) => harness.joinedSince(t, r), [t0[i], ROOM], { timeout: 30000 }).catch(() => {});
  }
  await sleep(500);
  for (const [i, p] of [A, B].entries()) {
    const r = await ev(p, (t) => ({
      closes: harness.events.filter((e) => e.t === 'state' && e.s === 'closed' && e.at >= t).map((e) => e.a),
      attempts: harness.reconnect.attempts.filter((a) => a >= t).map((a) => Math.round(a - t)),
      online: !!harness.welcome && harness.state === 'open',
      joined: harness.ctl.some((m) => m.t === 'roster' && m.at >= t),
    }), t0[i]);
    const s1 = await fresh(p);
    const sockets = s1.sockets - s0[i].sockets;
    report.measures[`restart${p.name}`] = { ...r, sockets };
    check(`restart ${p.name}: closed 1012, backed off, online again`, r.closes[0] === 1012 && r.online && r.joined && r.attempts.length >= 2 && r.attempts.length <= 6,
      `closes ${r.closes.join(',')}; attempts at ${r.attempts.join(', ')} ms; online ${r.online}`);
    check(`restart ${p.name}: one socket per attempt (no engine retry loop)`, sockets === r.attempts.length, `${sockets} sockets for ${r.attempts.length} attempts`);
  }
  A.sid = await ev(A, () => harness.welcome.sid);
  B.sid = await ev(B, () => harness.welcome.sid);
  const b0 = await fresh(B);
  await cmd(A, { op: 'tx', slot: 0 });
  await sleep(2000);
  await cmd(A, { op: 'tx', slot: -1 });
  await sleep(600);
  const b1 = await fresh(B);
  check('restart: audio flows again after the reconnect', b1.down.f - b0.down.f >= 45, `${b1.down.f - b0.down.f} frames`);
};

// a microphone the player refused: listen-only, with an event
steps.denied = async () => {
  const browser = await chromium.launch({
    executablePath: env.CHROME || undefined,
    // the fake permission UI answers "Block", as a player who refused
    args: ['--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream=deny', '--autoplay-policy=no-user-gesture-required'],
  });
  try {
    const C = await openPage(browser, 'C');
    await connectPage(C, claimsC);
    const t0 = await pageNow(C);
    await cmd(C, { op: 'tx', slot: 0 });
    await C.page.waitForFunction((t) => harness.events.some((e) => e.t === 'mic' && e.at >= t), t0, { timeout: 15000 }).catch(() => {});
    await cmd(C, { op: 'tx', slot: -1 });
    const mic = (await events(C, t0)).filter((e) => e.t === 'mic').map((e) => e.s);
    const talker = bot('talk', ['-in', WAV, '-loop', '1'], 950);
    const c0 = await fresh(C);
    await talker.done;
    const c1 = await fresh(C);
    check('mic denied: event "denied", no frames sent', mic[0] === 'denied' && c1.up.f === 0, `mic events ${JSON.stringify(mic)}, sent ${c1.up.f}`);
    check('mic denied: still hears the room (listen-only)', c1.down.dec - c0.down.dec > 100 && c1.state === 'open' && c1.errors === 0, `decoded ${c1.down.dec - c0.down.dec}, state ${c1.state}, errors ${c1.errors} ${c1.lastError}`);
    await C.context.close();
  } finally {
    await browser.close();
  }
};

// the near room (slot 3), when the relay has it (the welcome's "near"): A and
// B join near and list each other's creature on screen; A talks on slot 3
// while B gives A a place (hard left, hard right, centred at gain 0.5), and
// once on slot 0 for the reference. B's output per side: the probe's rms
// (left) and rmsR (right) over each spurt, and its peak
steps.near = async () => {
  const has = await ev(B, () => !!(harness.welcome && harness.welcome.near));
  if (!has) {
    console.log('near: this relay has no near room (no "near" in the welcome): skipped');
    report.measures.near = 'skipped: relay without near';
    return;
  }
  const t0 = await pageNow(B);
  await ctl(A, { t: 'join', room: 'near' });
  await ctl(B, { t: 'join', room: 'near' });
  for (const p of [A, B]) await p.page.waitForFunction((t) => harness.ctl.some((m) => m.t === 'roster' && m.room === 'near' && m.at >= t), t0, { timeout: 5000 });
  await ctl(A, { t: 'near', c: [claimsB.i] });
  await ctl(B, { t: 'near', c: [claimsA.i] });
  const seen = await B.page.waitForFunction(([t, sid]) => harness.ctl.some((m) => m.t === 'in' && m.room === 'near' && m.at >= t && JSON.stringify(m).includes(String(sid))), [t0, A.sid], { timeout: 5000 }).then(() => true, () => false);
  check('near: A and B see each other (in, room near)', seen, `B saw A in near: ${seen}`);
  const rooms = await ev(A, () => MythosVoice.stats().rooms);
  check('near: the engine tracks the near room on slot 3', rooms[3] === 'near', JSON.stringify(rooms));
  await cmd(B, { op: 'probe', on: true });
  const spurt = async (slot, place) => {
    if (place) await cmd(B, { op: 'spatial', sid: A.sid, g: place[0], p: place[1] });
    await sleep(300);
    await fresh(B); // clears B's level window
    await cmd(A, { op: 'tx', slot });
    await sleep(2200);
    await cmd(A, { op: 'tx', slot: -1 });
    await sleep(500);
    const m = (await fresh(B)).mix || {};
    return { l: r1(m.rms), r: r1(m.rmsR), peak: m.peak };
  };
  const ref = await spurt(0, null);
  const left = await spurt(3, [1, -1]);
  const right = await spurt(3, [1, 1]);
  const half = await spurt(3, [0.5, 0]);
  report.measures.near = { ref, left, right, half };
  const db = (x) => r1(20 * Math.log10(x));
  check('near: slot 0 reference centred on B', ref.l > -45 && Math.abs(ref.l - ref.r) < 0.5, JSON.stringify(ref));
  check('near: A on slot 3 placed hard left: B hears it on the left', left.l > -45 && left.l - left.r > 20, JSON.stringify(left));
  check('near: placed hard right: on the right', right.r > -45 && right.r - right.l > 20, JSON.stringify(right));
  check('near: centred at gain 0.5: both sides, 6 dB down (peak)', Math.abs(half.l - half.r) < 0.5 && Math.abs(db(half.peak / ref.peak) + 6) < 2, `${JSON.stringify(half)}, peak ${db(half.peak / ref.peak)} dB vs the reference`);
  await cmd(B, { op: 'probe', on: false });
  await cmd(B, { op: 'spatial', sid: A.sid, g: 1, p: 0 });
  await ctl(A, { t: 'leave', room: 'near' });
  await ctl(B, { t: 'leave', room: 'near' });
  await sleep(300);
};

// --- run ---------------------------------------------------------------------

let work;
let browserCdp;
let mainBrowser;

async function main() {
  work = mkdtempSync(join(tmpdir(), 'voz-e2e-'));
  if (!existsSync(WAV)) {
    await execP('sh', [join(here, 'make-fixtures.sh')]);
  }
  const server = await startServer(PAGE_PORT, { key: KEY, mint: env.VOZ_MINT });
  await startRelay();
  let browser;
  try {
    const order = ['ptt', 'near', 'vad', 'smute', 'mute', 'deaf', 'blur', 'test', 'prefs', 'eco', 'lastn', 'cpu', 'wake', 'asleep', 'vadroom', 'devices', 'meterperm', 'encfail', 'gesture', 'restart'];
    const todo = order.filter((s) => !only || only.has(s));
    if (todo.length) {
      browser = await chromium.launch({
        executablePath: env.CHROME || undefined,
        args: ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream', `--use-file-for-fake-audio-capture=${WAV}`, '--autoplay-policy=no-user-gesture-required'],
      });
      browserCdp = await browser.newBrowserCDPSession();
      mainBrowser = browser;
      A = await openPage(browser, 'A');
      B = await openPage(browser, 'B');
      await connectPage(A, claimsA);
      await connectPage(B, claimsB);
      console.log(`A sid ${A.sid}, B sid ${B.sid}`);
      for (const s of todo) {
        console.log(`--- ${s}`);
        try {
          await steps[s]();
        } catch (e) {
          check(`${s}: ran`, false, e.stack || e.message);
        }
      }
      report.measures.finalA = await fresh(A);
      report.measures.finalB = await fresh(B);
      const fa = report.measures.finalA;
      const fb = report.measures.finalB;
      check('no engine error swallowed by its guards (A and B, whole run)', fa.errors === 0 && fb.errors === 0, `A ${fa.errors} ${fa.lastError}, B ${fb.errors} ${fb.lastError}`);
      await browser.close();
      browser = null;
    }
    if (!only || only.has('denied')) {
      console.log('--- denied');
      try {
        await steps.denied();
      } catch (e) {
        check('denied: ran', false, e.stack || e.message);
      }
    }
  } finally {
    if (browser) await browser.close().catch(() => {});
    for (const b of bots) b.kill('SIGKILL');
    report.relayStats = await relayStats().catch(() => null);
    await stopRelay('SIGTERM');
    server.close();
    rmSync(work, { recursive: true, force: true });
  }
  const failed = report.checks.filter((c) => !c.ok);
  report.passed = report.checks.length - failed.length;
  report.failed = failed.length;
  console.log(JSON.stringify(report.measures, null, 1));
  console.log(`\n${report.passed} passed, ${report.failed} failed`);
  if (jsonOut) writeFileSync(jsonOut, JSON.stringify(report, null, 1));
  process.exitCode = failed.length ? 1 : 0;
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 2;
  for (const b of bots) b.kill('SIGKILL');
  if (relay) relay.kill('SIGKILL');
});
