// The page side of the C++ bridge, in Node (no browser, no emscripten):
//
//   node bridge.mjs
//
// MythosVoice runs with a fake emscripten Module (a heap, _malloc,
// stringToUTF8, lengthBytesUTF8, _free and _otc_voice_event that reads the
// text back the way voiceengine_web.cpp does) and a fake WebSocket. Commands
// arrive as the JSON text voiceengine_web.cpp sends. Checked: nothing reaches
// the game before its first command; events come in one batch per
// microtask, UTF-8 intact, every buffer freed; the hello; control messages
// both ways; AUDIO and BUNDLE parsing and the speaking edges; generation tags;
// a replaced or closed socket reports nothing; close codes; the side mouse
// button listeners and the push-to-talk key held across them; the relay's
// payload limit; a game that stops polling (a full inbox refuses batches):
// nothing is lost while it is short, and a long one ends the connection with
// one 'closed', the newest 'mic'/'devices'/'caps' kept.
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const here = dirname(fileURLToPath(import.meta.url));
// MV_ENGINE: another copy of the engine (lint.mjs --minify: the minified one)
const engine = readFileSync(process.env.MV_ENGINE || join(here, '..', 'mythos-voice.js'), 'utf8');

let failed = 0;
let passed = 0;
function check(name, ok, detail = '') {
  if (ok) passed++;
  else failed++;
  if (!ok || process.argv.includes('-v')) console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  ' + detail : ''}`);
}

// --- a fake emscripten runtime -------------------------------------------------
const heap = new Uint8Array(1 << 22);
let top = 8;
const live = new Set();
const batches = []; // what C++ would have received, parsed
const raw = [];
let inboxFull = false; // as otc_voice_event with its inbox full: refused (0)
let refused = 0;
const enc = new TextEncoder();
const dec = new TextDecoder();
const Module = {
  _malloc(n) {
    const p = top;
    top += (n + 7) & ~7;
    live.add(p);
    return p;
  },
  _free(p) {
    live.delete(p);
  },
  lengthBytesUTF8: (s) => enc.encode(s).length,
  stringToUTF8(s, p, max) {
    const b = enc.encode(s);
    if (b.length + 1 > max) throw new Error('stringToUTF8 overflow');
    heap.set(b, p);
    heap[p + b.length] = 0;
  },
  // as voiceengine_web.cpp: strlen + copy, then JSON parse on the game thread
  _otc_voice_event(p) {
    if (inboxFull) {
      refused++;
      return 0;
    }
    let e = p;
    while (heap[e]) e++;
    const text = dec.decode(heap.subarray(p, e));
    raw.push(text);
    batches.push(JSON.parse(text));
    return 1;
  },
};

// --- fake WebSocket, document, timers ----------------------------------------------
const sockets = [];
class FakeWebSocket {
  constructor(url, proto) {
    this.url = url;
    this.proto = proto;
    this.sent = [];
    this.readyState = 0;
    this.bufferedAmount = 0;
    this.closedWith = null;
    sockets.push(this);
  }
  send(x) {
    this.sent.push(typeof x === 'string' ? x : Array.from(x));
  }
  close(code) {
    this.closedWith = code || 1005;
    this.readyState = 3;
  }
  // test helpers
  open() {
    this.readyState = 1;
    this.onopen && this.onopen();
  }
  text(s) {
    this.onmessage && this.onmessage({ data: s });
  }
  bin(bytes) {
    this.onmessage && this.onmessage({ data: new Uint8Array(bytes).buffer });
  }
  drop(code) {
    this.readyState = 3;
    this.onclose && this.onclose({ code });
  }
}
const docListeners = [];
const docFns = new Map();
const document = {
  hidden: false,
  addEventListener: (type, fn, cap) => {
    docListeners.push(['+', type, cap]);
    docFns.set(type, fn);
  },
  removeEventListener: (type, fn, cap) => {
    docListeners.push(['-', type, cap]);
    if (docFns.get(type) === fn) docFns.delete(type);
  },
};
const mouse = (type, button) => docFns.get(type)({ type, button, preventDefault() {}, stopPropagation() {} });
let clock = 1000;
const window = { Module, WebSocket: FakeWebSocket, addEventListener() {}, removeEventListener() {} };
window.window = window;
const intervals = [];
const ctx = vm.createContext({
  window, document, WebSocket: FakeWebSocket,
  performance: { now: () => clock, timeOrigin: 0 },
  navigator: {}, Promise, JSON, Math, Map, Uint8Array, Float32Array, Array, String, Number, isFinite,
  setTimeout: (fn, ms) => setTimeout(fn, ms),
  clearTimeout,
  setInterval: (fn, ms) => {
    intervals.push(fn);
    return intervals.length;
  },
  clearInterval: (id) => {
    intervals[id - 1] = null;
  },
});
vm.runInContext(engine, ctx);
const V = window.MythosVoice;
const tick = () => new Promise((r) => setTimeout(r, 0)); // lets microtasks run
const events = () => batches.flat();
const cmd = (o) => V.cmd(JSON.stringify(o)); // the C++ sends text

// --- the checks ------------------------------------------------------------------
check('support() is 0 without WebCodecs (C++ then picks the lite engine)', V.support() === 0);
// (the shell is preprocessed before emscripten minifies it: not for the minified copy)
if (!process.env.MV_MINIFIED) {
  check('the worklet source has no three braces and no line starting with #', !/\{\{\{|\}\}\}/.test(V.workletSource()) && !V.workletSource().split('\n').some((l) => l.trim().startsWith('#')));
}

await tick();
check('nothing reaches C++ before its first command', batches.length === 0);

cmd({ op: 'connect', url: 'ws://127.0.0.1:7191/voz', tok: 'TOKEN', cl: 'web', b: '1.0 abc', g: 1 });
await tick();
const ws1 = sockets[0];
check('connect opens one WebSocket with the subprotocol', sockets.length === 1 && ws1.url === 'ws://127.0.0.1:7191/voz' && ws1.proto === 'mythos-voice.1' && ws1.binaryType === 'arraybuffer');
check('state connecting, tagged with the generation', events().some((e) => e.t === 'state' && e.s === 'connecting' && e.g === 1));

ws1.open();
await tick();
const nb = batches.length;
const hello = JSON.parse(ws1.sent[0]);
check('the hello goes first, in the protocol F shape', JSON.stringify(hello) === JSON.stringify({ t: 'hello', v: 1, tok: 'TOKEN', cl: 'web', b: '1.0 abc', a: 1 }), ws1.sent[0]);
check('state open', events().some((e) => e.t === 'state' && e.s === 'open' && e.g === 1));

// several events in one task: one batch
ws1.text('{"t":"welcome","sid":3,"now":1,"exp":2,"lim":{"pl":240,"fps":30,"bps":6000,"lastN":4}}');
ws1.text('{"t":"roster","room":"p:9:1","slot":0,"u":[[3,1,1,"Ana",0],[5,2,2,"Comércio Ünïcode ✓",0]]}');
ws1.text('{"t":"dir","rooms":[["pub:comercio","Comércio",1,100,50,0]]}');
await tick();
check('three events in one task arrive as one batch (one C++ call)', batches.length === nb + 1 && batches[batches.length - 1].length === 3, `${batches.length - nb} batch(es)`);
const roster = events().find((e) => e.t === 'ctl' && e.s.includes('roster'));
check('relay text passes through unchanged, UTF-8 intact', roster && JSON.parse(roster.s).u[1][3] === 'Comércio Ünïcode ✓' && roster.g === 1);

// big control messages go through the malloc'd copy
const big = JSON.stringify({ t: 'roster', room: 'g:45', slot: 1, u: Array.from({ length: 500 }, (_, i) => [i + 10, i, i, 'Membro Número ' + i, 0]) });
ws1.text(big);
await tick();
check('a 500-member roster reaches C++ whole (malloc path)', events().some((e) => e.t === 'ctl' && e.s === big), `${big.length} B`);

// audio: AUDIO and BUNDLE, speaking edges (the decoder is absent here: frames are dropped after the edge)
const audio = (flags, sid, seq, n) => [0x01, flags, sid & 255, sid >> 8, seq, ...new Array(n).fill(0x55)];
ws1.bin(audio(0, 5, 1, 20));
ws1.bin(audio(0, 5, 2, 20));
await tick();
check('a frame over 10 B: speaking on', events().filter((e) => e.t === 'spk' && e.a === 5 && e.b === 1).length === 1);
ws1.bin(audio(4, 5, 3, 20));
await tick();
check('END: speaking off', events().some((e) => e.t === 'spk' && e.a === 5 && e.b === 0));
ws1.bin(audio(0, 300, 1, 5));
await tick();
check('frames of 10 B or less are not speech', !events().some((e) => e.t === 'spk' && e.a === 300));
const entry = (flags, sid, seq, n) => [4 + n, flags, sid & 255, sid >> 8, seq, ...new Array(n).fill(0x33)];
ws1.bin([0x02, 2, ...entry(0, 6, 1, 30), ...entry(1, 7, 1, 40)]);
await tick();
check('BUNDLE: both speakers start', events().some((e) => e.t === 'spk' && e.a === 6 && e.b === 1) && events().some((e) => e.t === 'spk' && e.a === 7 && e.b === 1));
const before = V.stats().down.f;
ws1.bin([0x02, 2, 200, 0, 0]);
ws1.bin([0x01, 0, 1]);
ws1.bin([0x02, 3, ...entry(0, 8, 1, 30)]);
ws1.bin([0x09, 1, 2, 3, 4, 5, 6]);
await tick();
check('malformed binary messages are ignored (a short BUNDLE keeps its whole entries, as the relay\'s ParseDown)', V.stats().down.f - before === 1, `+${V.stats().down.f - before} frames`);
// speaking off after 300 ms without frames
clock += 400;
intervals.filter(Boolean).forEach((fn) => fn());
await tick();
check('300 ms without frames: speaking off', events().some((e) => e.t === 'spk' && e.a === 6 && e.b === 0) && events().some((e) => e.t === 'spk' && e.a === 7 && e.b === 0));

// control out
cmd({ op: 'ctl', json: '{"t":"join","room":"g:45"}' });
check('ctl: sent as text on the socket', ws1.sent[ws1.sent.length - 1] === '{"t":"join","room":"g:45"}');

// a new connect replaces the socket: the old one reports nothing
cmd({ op: 'connect', url: 'ws://127.0.0.1:7191/voz', tok: 'T2', cl: 'web', b: 'x', g: 2 });
await tick();
const ws2 = sockets[1];
const n1 = events().length;
ws1.drop(1006);
ws1.text('{"t":"welcome","sid":99}');
await tick();
check('a replaced socket is closed and reports nothing', ws1.closedWith === 1000 && events().length === n1 && events().slice(n1 - 1).every((e) => e.g !== 1 || e.t === 'spk'));
ws2.open();
ws2.drop(4403);
await tick();
const closed = events().filter((e) => e.t === 'state' && e.s === 'closed');
check('a relay close reports its code once, with the new generation', closed.length === 1 && closed[0].a === 4403 && closed[0].g === 2, JSON.stringify(closed));
check('the engine never reconnects by itself', sockets.length === 2);

// ctl on a closed socket goes nowhere
cmd({ op: 'ctl', json: '{"t":"dir"}' });
check('ctl while closed is dropped', !ws2.sent.includes('{"t":"dir"}'));

// disconnect: silent
cmd({ op: 'connect', url: 'ws://127.0.0.1:7191/voz', tok: 'T3', cl: 'web', b: 'x', g: 3 });
await tick();
const ws3 = sockets[2];
ws3.open();
await tick();
const n3 = events().length;
cmd({ op: 'disconnect' });
ws3.drop(1000);
await tick();
check('disconnect closes the socket and reports nothing', ws3.closedWith === 1000 && events().length === n3);

// the side mouse button listeners come and go with the setting
cmd({ op: 'pttMouse', btn: 4, slot: 0 });
const added = docListeners.filter((x) => x[0] === '+' && x[2] === true).map((x) => x[1]).sort().join(',');
cmd({ op: 'pttMouse', btn: 0, slot: -1 });
const removed = docListeners.filter((x) => x[0] === '-' && x[2] === true).map((x) => x[1]).sort().join(',');
check('pttMouse adds and removes mousedown/mouseup/auxclick (capture)', added === 'auxclick,mousedown,mouseup' && removed === added, `${added} / ${removed}`);

// push-to-talk: the key and the side mouse button, held together
cmd({ op: 'connect', url: 'ws://127.0.0.1:7191/voz', tok: 'T4', cl: 'web', b: 'x', g: 4 });
await tick();
const ws4 = sockets[3];
ws4.open();
ws4.text('{"t":"welcome","sid":9,"now":1,"exp":2,"lim":{"pl":100,"fps":30,"bps":6000,"lastN":4}}');
ws4.text('{"t":"roster","room":"p:9:1","slot":0,"u":[[9,1,1,"Ana",0]]}');
ws4.text('{"t":"roster","room":"g:45","slot":1,"u":[[9,1,1,"Ana",0]]}');
await tick();
check('welcome lim.pl is the payload limit for sending', V.stats().up.max === 100, `max ${V.stats().up.max}`);
cmd({ op: 'pttMouse', btn: 3, slot: 0 });
cmd({ op: 'tx', slot: 1 }); // the guild key, held
mouse('mousedown', 3);
const txDown = V.stats().tx;
mouse('mouseup', 3);
const txUp = V.stats().tx;
cmd({ op: 'tx', slot: -1 });
check('the mouse button held over the key talks on its slot, and its release gives the key back', txDown === 0 && txUp === 1 && V.stats().tx === -1, `down ${txDown}, up ${txUp}, after key ${V.stats().tx}`);
mouse('mousedown', 3);
cmd({ op: 'tx', slot: 1 });
cmd({ op: 'tx', slot: -1 }); // the key let go while the button is held
const txHeld = V.stats().tx;
mouse('mouseup', 3);
check('the key let go while the button is held: the button goes on, then all stops', txHeld === 0 && V.stats().tx === -1, `held ${txHeld}, after ${V.stats().tx}`);
cmd({ op: 'pttMouse', btn: 0, slot: -1 });

// a game thread that stops polling: its inbox refuses batches
await tick();
const nStall = events().length;
inboxFull = true;
ws4.text('{"t":"in","room":"p:9:1","u":[11,1,1,"Bia",0]}');
ws4.bin(audio(0, 11, 1, 20));
await tick();
check('a refused batch is kept: nothing reaches the game, the page waits', refused === 1 && events().length === nStall && V.stats().queue.stalled === true, `refused ${refused}, queue ${JSON.stringify(V.stats().queue)}`);
ws4.text('{"t":"out","room":"p:9:1","sid":11}');
await tick();
check('while stalled the page does not retry on every event', refused === 1, `refused ${refused}`);
inboxFull = false;
await new Promise((r) => setTimeout(r, 400));
const after = events().slice(nStall).map((e) => e.t === 'ctl' ? JSON.parse(e.s).t : e.t + (e.b !== undefined ? e.b : ''));
check('the game polls again: the kept events arrive, in order, none lost', JSON.stringify(after) === JSON.stringify(['in', 'spk1', 'out']), JSON.stringify(after));

// a long stall: more than the page keeps. The connection ends here, with
// one 'closed' at the end, the newest 'mic' kept, levels dropped
inboxFull = true;
clock += 6000; // past MIC_RETRY_MS: the press asks for the microphone again ('mic nodevice' here)
cmd({ op: 'tx', slot: 0 });
cmd({ op: 'tx', slot: -1 });
for (let i = 0; i < 600; i++) ws4.text(`{"t":"st","room":"p:9:1","sid":9,"f":${i & 1}}`);
await tick();
const q = V.stats().queue;
check('a long stall ends the connection (socket closed by the page, one resync)', ws4.closedWith === 1000 && q.resyncs === 1 && q.n <= 4, JSON.stringify(q));
const kept = V.stats().queue.n;
inboxFull = false;
await new Promise((r) => setTimeout(r, 400));
const tail = events().slice(-kept);
const last = tail[tail.length - 1];
check('...and the game then gets one closed 1006 of that generation, last', last.t === 'state' && last.s === 'closed' && last.a === 1006 && last.g === 4 && events().filter((e) => e.t === 'state' && e.g === 4 && e.s === 'closed').length === 1, JSON.stringify(tail));
const nEnd = events().length;
ws4.text('{"t":"roster","room":"x","slot":0,"u":[]}');
ws4.drop(1006);
await tick();
check('...after which the old socket says nothing', events().length === nEnd, `+${events().length - nEnd}`);
check('...and the newest mic state was kept through it', tail.some((e) => e.t === 'mic'), JSON.stringify(tail.map((e) => e.t)));
check('the engine did not reconnect by itself', sockets.length === 4);

// stats goes through the same path
cmd({ op: 'stats' });
await tick();
const stats = events().find((e) => e.t === 'stats');
check('stats: a JSON snapshot', stats && JSON.parse(stats.s).v === 1);

// garbage commands do nothing
for (const junk of ['', '{', 'null', '[]', '{"op":5}', '{"op":"nope"}', '{"op":"tx","slot":"x"}', '{"op":"uvol","sid":null,"x":"nan"}']) V.cmd(junk);
await tick();
check('malformed commands are ignored', true);

check('every buffer handed to C++ was freed', live.size === 0, `${live.size} left`);
check('every batch is a JSON array of events with a type', batches.every((b) => Array.isArray(b) && b.every((e) => typeof e.t === 'string')));

console.log(`${passed} passed, ${failed} failed`);
process.exitCode = failed ? 1 : 0;
