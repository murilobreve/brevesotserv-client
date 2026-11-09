// Checks that mythos-voice.js can be pasted into the emscripten shell, the
// way the WASM build does it (cmake/VoiceShell.cmake), without emscripten:
//
//   node lint.mjs [--browser]
//
// 1. the engine has no three braces in a row, no end of a script tag, no
//    "<!--"/"<script"/"<style", and no line that starts with a hash sign
//    (emscripten preprocesses the shell and takes those as directives);
// 2. cmake -P cmake/VoiceShell.cmake writes the page, byte for byte the shell
//    with the marker replaced (CMake keeps every ; and \);
// 3. the whole page still follows the preprocessor's rule (outside <style>);
// 4. --browser: the page, with {{{ SCRIPT }}} removed, defines MythosVoice in
//    Chromium under COOP/COEP and finds WebCodecs Opus support;
// 5. --minify: what the CI build does next. At -O1 and up, emscripten's link
//    step runs html-minifier-terser on the finished page (MINIFY_HTML, after
//    the shell was preprocessed and {{{ SCRIPT }}} filled in), with the flags
//    below, so the engine ships minified by terser. The minified engine is
//    written to ../tmp-min/mythos-voice.js, and worklet.mjs and bridge.mjs run
//    on it; e2e.mjs runs on it with MV_ENGINE=../tmp-min/mythos-voice.js.
//    html-minifier-terser comes from MV_MINIFIER (its package folder) or the
//    usual Node resolution (npm install --no-save html-minifier-terser@7.2.0,
//    the version emscripten pins).
import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync, mkdirSync } from 'node:fs';
import { gzipSync } from 'node:zlib';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, '../../..');
const jsPath = join(repo, 'browser/voice/mythos-voice.js');
const shellPath = join(repo, 'browser/shell.html');
const MARKER = '<script>/*MYTHOS_VOICE*/</script>';
let failed = 0;
const check = (name, ok, detail = '') => {
  if (!ok) failed++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  ' + detail : ''}`);
};

const js = readFileSync(jsPath, 'utf8');
const shell = readFileSync(shellPath, 'utf8');
check('engine: no three braces in a row', !js.includes('{{{') && !js.includes('}}}'));
check('engine: no </script, <script, <!--, <style', !/<\/script|<script|<!--|<style/i.test(js));
const hashLines = js.split('\n').map((l, i) => [i + 1, l]).filter(([, l]) => l.trim().startsWith('#'));
check('engine: no line starts with #', hashLines.length === 0, hashLines.map(([n]) => n).join(','));
check('engine: no backtick template strings (no ${ for CMake to see)', !js.includes('`'));
try {
  new Function(js);
  check('engine: parses', true);
} catch (e) {
  check('engine: parses', false, e.message);
}
check('shell: has the marker once', shell.split(MARKER).length === 2);
check('engine: size', true, `${js.length} B (${Math.round(js.length / 1024)} KB), gzip ${gzipSync(js).length} B`);

const work = mkdtempSync(join(tmpdir(), 'voz-lint-'));
let page = '';
try {
  const out = join(work, 'shell.voice.html');
  execFileSync('cmake', [`-DVOICE_SHELL_IN=${shellPath}`, `-DVOICE_JS=${jsPath}`, `-DVOICE_SHELL_OUT=${out}`, '-P', join(repo, 'cmake/VoiceShell.cmake')], { stdio: 'inherit' });
  page = readFileSync(out, 'utf8');
  const expected = shell.replace(MARKER, '<script>\n' + js + '</script>');
  check('cmake: the page is the shell with the engine pasted in, byte for byte', page === expected, `${page.length} B`);
  // the emscripten preprocessor: directives are lines starting with # outside <style>
  let inStyle = false;
  const bad = [];
  page.split('\n').forEach((line, i) => {
    if (line.includes('<style') && !inStyle) inStyle = true;
    if (line.includes('</style') && inStyle) {
      inStyle = false;
      return;
    }
    if (!inStyle && line.trim().startsWith('#')) bad.push(i + 1);
  });
  check('page: no preprocessor directive outside <style>', bad.length === 0, bad.join(','));
  check('page: {{{ SCRIPT }}} once, no other triple braces', page.split('{{{').length === 2 && page.includes('{{{ SCRIPT }}}'));
} catch (e) {
  check('cmake -P VoiceShell.cmake', false, e.message);
}

if (process.argv.includes('--browser') && page) {
  const require = createRequire(import.meta.url);
  const { chromium } = require('playwright');
  const { startServer } = await import('./server.mjs');
  mkdirSync(join(here, '..', 'tmp-lint'), { recursive: true });
  const file = join(here, '..', 'tmp-lint', 'index.html');
  writeFileSync(file, page.replace('{{{ SCRIPT }}}', ''));
  const server = await startServer(8293);
  const browser = await chromium.launch();
  try {
    const p = await browser.newPage();
    await p.goto('http://127.0.0.1:8293/tmp-lint/index.html');
    const r = await p.waitForFunction(() => window.MythosVoice && MythosVoice.support() !== 2 && { support: MythosVoice.support(), isolated: self.crossOriginIsolated, module: typeof Module }, null, { timeout: 10000 });
    const v = await r.jsonValue();
    check('page in Chromium: MythosVoice loaded next to Module, Opus supported', v.support === 1 && v.module === 'object', JSON.stringify(v));
  } finally {
    await browser.close();
    server.close();
    rmSync(join(here, '..', 'tmp-lint'), { recursive: true, force: true });
  }
}
// emscripten's minify_html() options at -g0 (tools/link.py)
const EMCC_MINIFY = ['--collapse-whitespace', '--collapse-inline-tag-whitespace', '--remove-comments', '--remove-tag-whitespace',
  '--sort-attributes', '--sort-class-name', '--decode-entities', '--collapse-boolean-attributes', '--remove-attribute-quotes',
  '--remove-redundant-attributes', '--remove-script-type-attributes', '--remove-style-link-type-attributes', '--use-short-doctype',
  '--minify-css', 'true', '--minify-js', 'true'];

if (process.argv.includes('--minify') && page) {
  let cli = process.env.MV_MINIFIER ? join(process.env.MV_MINIFIER, 'cli.js') : '';
  if (!cli) {
    try {
      cli = createRequire(import.meta.url).resolve('html-minifier-terser/cli.js');
    } catch (e) {
      cli = '';
    }
  }
  if (!cli || !existsSync(cli)) {
    check('minify: html-minifier-terser found', false, 'set MV_MINIFIER to its package folder, or npm install --no-save html-minifier-terser@7.2.0');
  } else {
    const src = join(work, 'page.html');
    const min = join(work, 'page.min.html');
    // as emscripten: {{{ SCRIPT }}} is already the loader when the page is minified
    writeFileSync(src, page.replace('{{{ SCRIPT }}}', '<script async type="text/javascript" src="otclient.js"></script>'));
    execFileSync(process.execPath, [cli, src, '-o', min, ...EMCC_MINIFY], { stdio: 'inherit' });
    const out = readFileSync(min, 'utf8');
    const scripts = [...out.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/g)].map((m) => m[1]);
    const engine = scripts.find((x) => x.includes('MythosVoice'));
    check('minify: the engine is still one script of the page, minified', !!engine && engine.length < js.length * 0.7,
      engine ? `${engine.length} B, gzip ${gzipSync(engine).length} B (page ${out.length} B)` : 'not found');
    if (engine) {
      try {
        new Function(engine);
        check('minify: the minified engine parses', true);
      } catch (e) {
        check('minify: the minified engine parses', false, e.message);
      }
      const dir = join(here, '..', 'tmp-min');
      mkdirSync(dir, { recursive: true });
      const file = join(dir, 'mythos-voice.js');
      writeFileSync(file, engine);
      for (const t of ['worklet.mjs', 'bridge.mjs']) {
        let text = '';
        let ok = true;
        try {
          text = execFileSync(process.execPath, [join(here, t)], { env: { ...process.env, MV_ENGINE: file, MV_MINIFIED: '1' }, encoding: 'utf8' });
        } catch (e) {
          ok = false;
          text = String(e.stdout || '') + String(e.stderr || '');
        }
        check(`minify: ${t} on the minified engine`, ok, text.trim().split('\n').filter((l) => /FAIL|passed/.test(l)).join(' | '));
      }
      console.log(`      e2e on it: MV_ENGINE=${file} node e2e.mjs`);
    }
  }
}

rmSync(work, { recursive: true, force: true });
console.log(failed ? `${failed} failed` : 'all passed');
process.exitCode = failed ? 1 : 0;
