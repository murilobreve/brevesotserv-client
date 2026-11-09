// Static server for the voice test page, with the headers of the real game
// page (COOP same-origin + COEP require-corp: crossOriginIsolated), plus
// /mint, which mints a relay token with vozmint (the stand-in for canary's
// opcode 142 tokens when the page reconnects on its own).
//
//   node server.mjs [port]        (default 8291; 127.0.0.1 only)
//   env VOZ_MINT (vozmint binary), VOZ_KEY (key file), MV_ENGINE (serve this
//   file as /mythos-voice.js instead: the minified copy of lint.mjs --minify)
//
// Serves browser/voice/ at /, so the page is /test/index.html and the engine
// it loads is /mythos-voice.js.
import { createServer } from 'node:http';
import { execFile } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import { dirname, extname, join, normalize, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = normalize(join(here, '..'));
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8', '.json': 'application/json', '.wav': 'audio/wav' };

export function mint(claims, opts = {}) {
  const bin = opts.mint || process.env.VOZ_MINT || '/tmp/qa/voice/bin/vozmint';
  const key = opts.key || process.env.VOZ_KEY || '/tmp/qa/voice/voz.key';
  return new Promise((resolve, reject) => {
    execFile(bin, ['-key', key, '-claims', JSON.stringify(claims)], (err, out) => (err ? reject(err) : resolve(out.trim())));
  });
}

export function startServer(port = 8291, opts = {}) {
  const server = createServer(async (req, res) => {
    const headers = {
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'require-corp',
      'Cross-Origin-Resource-Policy': 'same-origin',
      'Cache-Control': 'no-store',
    };
    const url = new URL(req.url, 'http://127.0.0.1');
    try {
      if (url.pathname === '/mint') {
        const claims = JSON.parse(url.searchParams.get('claims') || '{}');
        const tok = await mint(claims, opts);
        res.writeHead(200, { ...headers, 'Content-Type': 'text/plain' });
        res.end(tok);
        return;
      }
      let path = normalize(join(root, decodeURIComponent(url.pathname === '/' ? '/test/index.html' : url.pathname)));
      if (process.env.MV_ENGINE && url.pathname === '/mythos-voice.js') {
        path = process.env.MV_ENGINE;
      } else if (!path.startsWith(root + sep)) {
        throw Object.assign(new Error('outside'), { code: 'ENOENT' });
      }
      const body = await readFile(path);
      res.writeHead(200, { ...headers, 'Content-Type': TYPES[extname(path)] || 'application/octet-stream' });
      res.end(body);
    } catch (err) {
      res.writeHead(err.code === 'ENOENT' ? 404 : 500, headers);
      res.end(String(err.message || err));
    }
  });
  return new Promise((resolve) => server.listen(port, '127.0.0.1', () => resolve(server)));
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const port = Number(process.argv[2] || process.env.PORT || 8291);
  startServer(port).then(() => console.log(`voice test page: http://127.0.0.1:${port}/test/index.html`));
}
