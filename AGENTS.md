# AGENTS.md

## AGENTS.md Loading Budget

- Keep this root file limited to repository-wide invariants and precise routing gates; place detailed workflows in versioned documentation or skills.
- Codex applies a combined instruction budget (32 KiB by default) across global, root, and nested guidance. Keep mandatory gates first and preserve headroom for narrower scopes.
- Do not raise `project_doc_max_bytes` as the first response to oversized guidance; remove duplication and route conditional detail first.

## Client Assets Gate (Mandatory)

Any change touching client-assets auto-installation must preserve the runtime contract below:

1. **Final install paths must remain OTC-standard**
   - `data/things/<version>/`
   - `data/sounds/<version>/`
   - runtime extras in expected runtime locations (for example `bin/*` when distributed upstream)

2. **No alternate permanent source of truth**
   - Do not move runtime loading to `client-assets/` (or any new root) as the primary runtime path.
   - Temporary/cache directories are allowed only as transient staging, never as final runtime source.

3. **Security defaults stay strict unless explicitly justified**
   - `strictManifestSha256 = true`
   - `allowRawFallbackHashMismatch = false`

4. **Cross-platform build safety**
   - Android must not require unsupported `libarchive` linkage.
   - Desktop archive extraction behavior must remain functional.

5. **Verification required in PR description**
   - Explicitly state tested install paths and expected runtime load behavior.

Reference: `docs/client-assets-auto-install.md`

## Per-Kill Hot Paths

- An area spell that kills many monsters brings, in one frame, a text message, experience, capacity and inventory counts per corpse. Handlers of those signals (`g_game.onTextMessage`, `LocalPlayer` experience/level/capacity, `g_game.updateInventoryItems`, extended opcodes sent on kills or level ups) must not redo a whole window or list each time: update once on the next frame (`scheduleEvent(fn, 1)` behind a pending flag, as `game_skills`, the stats bar and `game_actionbar` do), or only when the window is visible (`game_ascensao`).
- Validate in the browser client: 30 monsters killed together with a normal character, `g_stats` per packet type before and after; the frame of the kills must not grow with what the change adds.

## Dead Creatures in Deferred Code

- A creature looked up by id after the moment it was sent (a scheduled event, an art's tick, a `later` callback) may have died: `g_map.getCreatureById` still finds it, `isDead()` is true and `getPosition()` is nil. Never hand that nil to the engine (`g_map.getTile`, `art.particles`, `art.play`): use `layerCreaturePosition(id)` in `game_skillshot`, or check `isDead()` and the position first.
- A C++ function that throws inside a call from Lua is raised as a Lua error after its catch block (`LuaInterface::luaCppFunctionCallback`, `lua_dofile`, `lua_loadfile`, `loadFiles`); raising it inside the catch closed the Windows client (LuaJIT unwinds with SEH). Keep any new `lua_error` out of catch blocks.
- Validate in the browser client: root a monster with Raízes Errantes (`exori tera vis`) and kill it while it is held; no "Lua exception" may follow in the log.

## Browser Voice Engine (`browser/voice/mythos-voice.js`)

- It is pasted into index.html inside the emscripten shell (`cmake/VoiceShell.cmake`): never three braces in a row, `</script`, or a line starting with `#` (emscripten preprocesses the shell). `shell.html` shows the crash screen on any uncaught page error: every engine callback goes through `safe()`.
- The game thread never waits on the page: commands with `MAIN_THREAD_ASYNC_EM_ASM`, events through `otc_voice_event` into a queue drained by `g_voice.poll()`. No new synchronous `MAIN_THREAD_EM_ASM` per frame.
- Desktop compiles none of it while `TOGGLE_FRAMEWORK_VOICE` is OFF (default outside WASM); keep every voice line in `luafunctions.cpp`/`graphicalapplication.cpp` under `#ifdef FRAMEWORK_VOICE`.
- Validate: in `browser/voice/test/`, `node lint.mjs --browser`, `node worklet.mjs`, `node bridge.mjs`, `node e2e.mjs` (local relay), and `luajit tools/voz-luatest/game_voice_test.lua`.

## Narrow Rules (recurring defects)

- `AttachedEffect` reads its duration only when it is attached: `setDuration` after `tile:attachEffect` does nothing. To end a skillshot layer early, schedule `detachArt` (`game_skillshot`).
- Client text is Latin-1 in both builds (the fonts draw one glyph per byte). Convert at the boundaries only: UTF-8 to Latin-1 for browser input and paste; Latin-1 to UTF-8 for anything sent to the site or put in JSON for it (`stdext::latin1_to_utf8`, `siteText` in `httplogin.cpp`, `CharacterList.siteText`). `data/locales/pt.lua` is cp1252.
- PT-BR text in a fixed-width window that does not wrap must fit the window's content width; measure it with the font's glyph widths (rightmost filled column + 1, `spacing` and `space-width` from the `.otfont`). A widget's text is clipped to the widget's rect moved by `text-offset`, so a checkbox label wider than `width - text-offset` runs over the next widget.
- `client_updater`: a same-version repair runs only against a manifest whose `versao` equals `versao.json`; an older manifest (a stale `main/` cache, a `-SemEnviar` test build) changes nothing. Every check goes through `getJSONWithin` (a deadline, then `HTTP.cancel`): the native HTTP client has one thread for every request. A periodic check reads only `<canal>/versao.json`; the commit and the manifest only when that number goes up, never twice for the same commit.
- A request a module sends by itself when the game starts waits `g_game.spreadDelay(min, max)` (gamelib), so a login rush does not bring every client's requests in the same second; calls of one burst come `SPREAD_STEP` apart.
- `client_assets`: a missing sprite sheet offers the download but never locks the player out ("Play anyway"; still missing after a download in the same session opens the game). Only missing core files (appearances, staticdata) are required.
- Extended opcode 139 is the client build report (`client_updater` -> server `scripts/custom/client_version.lua`); check the server's opcode list before taking a new number.
