// Mythos Voz: the native engine (this harness) against the browser engine
// (browser/voice/mythos-voice.js on its test page), both directions, through
// a local relay. Headless Chromium with its fake microphone playing a WAV.
//
//   node browser.mjs --bin <voz-native-test> --wav fala.wav --work <dir>
//
// Environment: VOZ_URL (ws://127.0.0.1:7391/voz: a relay started with
// -origin http://127.0.0.1:$PAGE_PORT), PAGE_PORT (8391), VOZ_MINT, VOZ_KEY
// (as browser/voice/test/server.mjs), CHROME (else Playwright's Chromium).
// Prints one JSON line per check and a summary; exit 1 if a check failed.
import { spawn } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { startServer, mint } from '../../browser/voice/test/server.mjs';

const require = createRequire(import.meta.url);
let playwright;
try {
  playwright = require('playwright');
} catch (e) {
  playwright = require('/opt/node22/lib/node_modules/playwright');
}

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const arg = (k, d) => {
  const i = args.indexOf(k);
  return i >= 0 ? args[i + 1] : d;
};
const BIN = arg('--bin');
const WAV = arg('--wav');
const WORK = arg('--work', '/tmp');
const URL_WS = process.env.VOZ_URL || 'ws://127.0.0.1:7391/voz';
const PAGE_PORT = Number(process.env.PAGE_PORT || 8391);
const PAGE = `http://127.0.0.1:${PAGE_PORT}/test/index.html`;
const ROOM = 'p:8:1';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const results = [];

function check(name, ok, detail) {
  results.push({ name, ok: !!ok, detail });
  console.log(JSON.stringify({ check: name, ok: !!ok, detail }));
}

// the harness as a child; resolves with its JSON lines once it exits
function harness(argv, env = {}) {
  const p = spawn(BIN, argv, { env: { ...process.env, ...env }, stdio: ['ignore', 'pipe', 'pipe'] });
  const lines = [];
  let buf = '';
  let err = '';
  p.stdout.on('data', (d) => {
    buf += d;
    let i;
    while ((i = buf.indexOf('\n')) >= 0) {
      const l = buf.slice(0, i);
      buf = buf.slice(i + 1);
      try {
        lines.push(JSON.parse(l));
      } catch (e) {
        err += l + '\n';
      }
    }
  });
  p.stderr.on('data', (d) => (err += d));
  p.done = new Promise((resolve) => p.on('exit', (code) => resolve({ code, lines, err })));
  p.lines = lines;
  return p;
}

function alsoftConf(name, wavOut) {
  const conf = join(WORK, `${name}.conf`);
  writeFileSync(conf, `[general]\ndrivers = wave\nchannels = mono\nsample-type = int16\nfrequency = 48000\n[wave]\nfile = ${wavOut}\n`);
  return { ALSOFT_CONF: conf, ALSOFT_DRIVERS: 'wave' };
}

async function waitFor(fn, ms, step = 100) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    if (fn()) return true;
    await sleep(step);
  }
  return false;
}

const server = await startServer(PAGE_PORT);
const browser = await playwright.chromium.launch({
  executablePath: process.env.CHROME || undefined,
  args: ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream', `--use-file-for-fake-audio-capture=${WAV}`,
    '--autoplay-policy=no-user-gesture-required'],
});
let exitCode = 0;
try {
  const context = await browser.newContext();
  const page = await context.newPage();
  const pageErrors = [];
  page.on('pageerror', (e) => pageErrors.push(e.message));
  await page.goto(PAGE);
  await page.waitForFunction(() => window.MythosVoice && MythosVoice.support() !== 2, null, { timeout: 10000 });
  const supported = await page.evaluate(() => MythosVoice.support());
  check('browser: WebCodecs Opus supported in this Chromium', supported === 1, `support ${supported}`);
  const tok = await mint({ a: 41, c: 401, i: 4001, n: 'Web', p: ROOM, pl: 1, lv: 60, pub: 1 });
  await page.evaluate(([u, t, r]) => harness.connect(u, t, r), [URL_WS, tok, ROOM]);
  await page.waitForFunction((r) => harness.welcome && harness.ctl.some((m) => m.t === 'roster' && m.room === r), ROOM, { timeout: 10000 });
  const webSid = await page.evaluate(() => harness.welcome.sid);
  await page.evaluate(() => MythosVoice.cmd({ op: 'probe', on: true })); // keeps the audio context awake, mixer RMS

  // -- browser talks, the native engine listens (real OpenAL playback, wave backend)
  {
    const outWav = join(WORK, 'out-web2native.wav');
    const htok = await mint({ a: 42, c: 402, i: 4002, n: 'Nativo', p: ROOM, lv: 60, pub: 1 });
    const h = harness(['--url', URL_WS, '--tok', htok, '--room', ROOM, '--recv', outWav, '--dur', '11', '--quiet'], alsoftConf('web2native', outWav));
    await waitFor(() => h.lines.some((l) => l.ev === 'ctl' && String(l.s).includes('"roster"')), 5000);
    await sleep(500);
    const a0 = await page.evaluate(() => MythosVoice.freshStats());
    await page.evaluate(() => MythosVoice.cmd({ op: 'tx', slot: 0 }));
    await sleep(6000);
    await page.evaluate(() => MythosVoice.cmd({ op: 'tx', slot: -1 }));
    await sleep(300);
    const a1 = await page.evaluate(() => MythosVoice.freshStats());
    const r = await h.done;
    const sum = r.lines.find((l) => l.summary) || {};
    const st = sum.stats || {};
    const sent = a1.up.f - a0.up.f;
    const got = st.down ? st.down.f : -1;
    check('web -> native: frames received', got >= sent - 2 && got <= sent && sent >= 140, `browser sent ${sent}, native got ${got}, decoded ${st.down && st.down.dec}, decErr ${st.down && st.down.decErr}`);
    check('web -> native: played without concealment or underruns', st.mix && st.mix.played >= got - 1 && st.mix.underruns === 0,
      `played ${st.mix && st.mix.played}, conceal ${st.mix && st.mix.conceal}, underruns ${st.mix && st.mix.underruns}, late ${st.mix && st.mix.late}`);
    const spk = r.lines.filter((l) => l.ev === 'spk' && l.a === webSid).map((l) => l.b);
    check('web -> native: speaking on then off for the browser sid', spk.length >= 2 && spk[0] === 1 && spk[spk.length - 1] === 0, spk.join(' '));
    const cmp = harness(['--compare', WAV, outWav, '--min-db', '-35']);
    const c = (await cmp.done).lines[0] || {};
    // the browser's own gain control and noise suppression change the level:
    // the shape is what must survive (bursts loud, gaps quiet)
    check('web -> native: OpenAL output has the bursts (loud and quiet windows)', c.loudWindows >= 8 && c.quietStayQuiet >= 8,
      `lag ${c.lagMs} ms, ${c.loudWindows} loud windows, mean |diff| ${c.meanAbsDb && c.meanAbsDb.toFixed(2)} dB, ${c.quietStayQuiet}/${c.quietWindows} quiet stay quiet`);
    check('web -> native: harness exit code 0', r.code === 0, `exit ${r.code}${r.err ? ' ' + r.err.slice(0, 300) : ''}`);
  }

  // -- the native engine talks, the browser listens
  {
    const htok = await mint({ a: 43, c: 403, i: 4003, n: 'Nativo2', p: ROOM, lv: 60, pub: 1 });
    const b0 = await page.evaluate(() => MythosVoice.freshStats());
    const t0 = await page.evaluate(() => performance.now());
    const h = harness(['--url', URL_WS, '--tok', htok, '--room', ROOM, '--send', WAV, '--dur', '10.5', '--quiet']);
    const r = await h.done;
    await sleep(800);
    const b1 = await page.evaluate(() => MythosVoice.freshStats());
    const sum = r.lines.find((l) => l.summary) || {};
    const up = (sum.stats && sum.stats.up) || {};
    const got = b1.down.f - b0.down.f;
    check('native -> web: frames received by the browser', up.f >= 255 && got >= up.f - 2 && got <= up.f, `native sent ${up.f}, browser got ${got}`);
    check('native -> web: the browser decoded every frame', b1.down.dec - b0.down.dec >= got - 1 && b1.down.decErr === b0.down.decErr,
      `decoded ${b1.down.dec - b0.down.dec}, errors ${b1.down.decErr - b0.down.decErr}`);
    const mix = b1.mix || {};
    check('native -> web: browser mixer output RMS over -45 dBFS', mix.rms > -45, `rms ${mix.rms && mix.rms.toFixed(1)} dBFS, peak ${mix.peak && mix.peak.toFixed(2)}, conceal ${mix.conceal}, late ${mix.late}`);
    const ev = await page.evaluate(([t, sid]) => harness.events.filter((e) => e.at >= t && e.t === 'spk' && e.a === sid).map((e) => e.b), [t0, sum.sid]);
    check('native -> web: speaking on then off at the browser', ev.length >= 2 && ev[0] === 1 && ev[ev.length - 1] === 0, ev.join(' '));
    check('native -> web: harness exit code 0', r.code === 0, `exit ${r.code}${r.err ? ' ' + r.err.slice(0, 300) : ''}`);
  }
  check('browser: no page error', pageErrors.length === 0, pageErrors.join(' | '));
  await page.evaluate(() => harness.disconnect());
  await context.close();
} catch (e) {
  check('browser test ran', false, String(e && e.stack || e));
} finally {
  await browser.close();
  server.close();
}
const failed = results.filter((r) => !r.ok).length;
console.log(JSON.stringify({ summary: 'browser', checks: results.length, failed }));
process.exit(failed ? 1 : exitCode);
